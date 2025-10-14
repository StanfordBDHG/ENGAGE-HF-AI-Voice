#!/usr/bin/env python3
"""Generate consolidated questionnaire reports.

This script loads FHIR Questionnaire definitions and QuestionnaireResponse data
from the ENGAGE-HF Voice AI decrypted session export and produces:

* An Excel workbook with a summary sheet plus one sheet per session.
* A CSV summary mirroring the summary sheet.

Each per-session worksheet contains the responses from all available
questionnaires (e.g., KCCQ-12, well-being comparison, vitals).

The script requires pandas (with an Excel writer backend such as xlsxwriter or
openpyxl). Install via "pip install pandas xlsxwriter" if needed.
"""
from __future__ import annotations

import argparse
import json
import re
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Mapping, Optional, Sequence, Tuple

import pandas as pd


SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT_DIR = SCRIPT_DIR.parent / "Output"

QUESTIONNAIRE_ORDER = [
    "Patient Vitals",
    "KCCQ-12",
    "Patient Well-being Comparison",
]
QUESTIONNAIRE_PRIORITY = {title: index for index, title in enumerate(QUESTIONNAIRE_ORDER)}


@dataclass
class QuestionInfo:
    """Metadata about a single questionnaire item."""

    link_id: str
    text: str
    section: str
    answer_map: Mapping[str, str]
    q_type: str


@dataclass
class AnswerRow:
    """Flattened questionnaire response entry."""

    questionnaire: str
    link_id: str
    question: str
    section: str
    code: Optional[str]
    display: Optional[str]
    raw_value: Any
    choices: Optional[str] = None


@dataclass
class QuestionnaireResponseBundle:
    """Container for a questionnaire response and its flattened answers."""

    questionnaire_id: str
    title: str
    authored: Optional[str]
    subject: Optional[str]
    answers: List[AnswerRow] = field(default_factory=list)




def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def normalise_text(value: Optional[str]) -> str:
    if not value:
        return ""
    return re.sub(r"\s+", " ", value.strip())


CALL_TIMESTAMP_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}$")


def parse_timestamp(value: Optional[str]) -> Optional[pd.Timestamp]:
    if not value:
        return None
    value = value.strip()
    if not value:
        return None
    if CALL_TIMESTAMP_PATTERN.match(value):
        parts = value.split("-")
        date_part = "-".join(parts[:3])
        time_part = ":".join(parts[3:])
        value = f"{date_part}T{time_part}"
    timestamp = pd.to_datetime(value, errors="coerce", utc=True)
    if pd.isna(timestamp):
        return None
    if isinstance(timestamp, pd.Timestamp) and timestamp.tzinfo is not None:
        timestamp = timestamp.tz_convert("UTC").tz_localize(None)
    return timestamp


def format_answer_choices(answer_map: Mapping[str, str]) -> Optional[str]:
    if not answer_map:
        return None
    pairs = [f"{code}: {label}" for code, label in sorted(answer_map.items(), key=lambda item: item[0])]
    return "; ".join(pairs)


def build_answer_label(answer: AnswerRow) -> str:
    questionnaire_name = normalise_text(answer.questionnaire)
    question = normalise_text(answer.question)
    section = normalise_text(answer.section)

    parts: List[str] = []
    if questionnaire_name:
        parts.append(questionnaire_name)
    if question:
        parts.append(question)

    label = " | ".join(parts)
    if section and section not in label and section not in question:
        label = f"{label} ({section})" if label else section
    if answer.link_id:
        label = f"{label} [{answer.link_id}]"

    label = re.sub(r"[\r\n\t]", " ", label)
    label = re.sub(r"\s+", " ", label).strip()
    return label[:200]


def build_metadata_label(questionnaire_title: str, descriptor: str, link_id: Optional[str] = None) -> str:
    title = normalise_text(questionnaire_title)
    label = f"{title} | {descriptor}" if title else descriptor
    if link_id:
        label = f"{label} [{link_id}]"
    label = re.sub(r"[\r\n\t]", " ", label)
    label = re.sub(r"\s+", " ", label).strip()
    return label[:200]


def build_question_bank(questionnaire: Mapping[str, Any]) -> Dict[str, QuestionInfo]:
    bank: Dict[str, QuestionInfo] = {}

    def walk(items: Sequence[Mapping[str, Any]], parents: List[str]) -> None:
        for item in items:
            link_id: Optional[str] = item.get("linkId")
            text = normalise_text(item.get("text"))
            item_type = item.get("type", "")
            section = " > ".join(p for p in parents if p)

            answer_map: Dict[str, str] = {}
            for option in item.get("answerOption", []):
                value_coding = option.get("valueCoding")
                if not value_coding:
                    continue
                code = value_coding.get("code") or value_coding.get("id")
                if code is None:
                    continue
                answer_map[str(code)] = normalise_text(value_coding.get("display") or str(code))

            if link_id and item_type != "group":
                bank[link_id] = QuestionInfo(
                    link_id=link_id,
                    text=text or link_id,
                    section=section,
                    answer_map=answer_map,
                    q_type=item_type,
                )

            child_parents = parents
            if text:
                child_parents = [*parents, text]

            if item.get("item"):
                walk(item["item"], child_parents)

    walk(questionnaire.get("item", []), [])
    return bank


def extract_answer_value(answer: Mapping[str, Any]) -> tuple[Any, Optional[str]]:
    for key in (
        "valueString",
        "valueInteger",
        "valueDecimal",
        "valueDate",
        "valueTime",
        "valueBoolean",
        "valueCoding",
    ):
        if key in answer:
            value = answer[key]
            if key == "valueCoding" and isinstance(value, Mapping):
                code = value.get("code") or value.get("id")
                display = value.get("display")
                return code, display
            return value, None
    return None, None


def flatten_response(
    response: Mapping[str, Any],
    questionnaire_title: str,
    question_bank: Mapping[str, QuestionInfo],
) -> QuestionnaireResponseBundle:
    bundle = QuestionnaireResponseBundle(
        questionnaire_id=questionnaire_title,
        title=questionnaire_title,
        authored=response.get("authored"),
        subject=(response.get("subject") or {}).get("reference"),
    )

    def walk(items: Sequence[Mapping[str, Any]], active_sections: List[str]) -> None:
        for item in items:
            link_id = item.get("linkId")
            question_info = question_bank.get(link_id)
            section = question_info.section if question_info else " > ".join(active_sections)
            question_text = question_info.text if question_info else link_id or "Unknown"

            if question_info is None:
                # Skip answers for items not present in the reference questionnaire definition.
                continue

            for answer in item.get("answer", []):
                value, coding_display = extract_answer_value(answer)
                display = coding_display
                code: Optional[str] = None

                if question_info.answer_map:
                    key = str(value)
                    if key in question_info.answer_map:
                        display = question_info.answer_map[key]
                        code = key
                    else:
                        # Attempt to handle numeric answers stored as ints vs. strings.
                        if isinstance(value, (int, float)):
                            key_num = str(int(value)) if isinstance(value, float) and value.is_integer() else str(value)
                            if key_num in question_info.answer_map:
                                display = question_info.answer_map[key_num]
                                code = key_num
                elif display is None and value is not None:
                    display = str(value)

                if display is None and value is not None:
                    display = str(value)

                if code is None and value is not None and isinstance(value, str):
                    code = value

                choices = format_answer_choices(question_info.answer_map) if question_info else None

                bundle.answers.append(
                    AnswerRow(
                        questionnaire=questionnaire_title,
                        link_id=link_id or "",
                        question=question_text or link_id or "",
                        section=section,
                        code=code,
                        display=display,
                        raw_value=value,
                        choices=choices,
                    )
                )

            child_sections = active_sections
            if question_text:
                child_sections = [*active_sections, question_text]
            if "item" in item:
                walk(item["item"], child_sections)

    walk(response.get("item", []), [])
    return bundle

def collect_questionnaire_data(root: Path) -> Tuple[Dict[str, List[QuestionnaireResponseBundle]], List[Dict[str, Any]]]:
    sessions: Dict[str, List[QuestionnaireResponseBundle]] = defaultdict(list)
    question_catalog: List[Dict[str, Any]] = []

    questionnaire_entries: List[Tuple[int, str, Path, Dict[str, QuestionInfo]]] = []

    for q_path in sorted(root.glob("*.json")):
        if q_path.name.startswith("."):
            continue
        questionnaire = load_json(q_path)
        if questionnaire.get("resourceType") != "Questionnaire":
            continue
        title = questionnaire.get("title") or q_path.stem
        question_bank = build_question_bank(questionnaire)
        priority = QUESTIONNAIRE_PRIORITY.get(title, len(QUESTIONNAIRE_ORDER))
        questionnaire_entries.append((priority, title, q_path, question_bank))

    questionnaire_entries.sort(key=lambda entry: (entry[0], entry[1]))

    for _priority, title, q_path, question_bank in questionnaire_entries:
        for question_info in question_bank.values():
            question_catalog.append(
                {
                    "Questionnaire": title,
                    "Section": normalise_text(question_info.section),
                    "Question": normalise_text(question_info.text),
                    "LinkId": question_info.link_id,
                    "Type": question_info.q_type,
                    "Possible Choices": format_answer_choices(question_info.answer_map),
                }
            )

        response_dir = root / q_path.stem
        if not response_dir.is_dir():
            continue

        for response_path in sorted(response_dir.glob("*.json")):
            if response_path.name.startswith("."):
                continue
            session_id = response_path.stem
            response_json = load_json(response_path)
            bundle = flatten_response(response_json, title, question_bank)
            sessions[session_id].append(bundle)

    return sessions, question_catalog

def build_summary_dataframe(
    sessions: Mapping[str, List[QuestionnaireResponseBundle]],
) -> pd.DataFrame:
    rows: List[Dict[str, Any]] = []

    for session_id in sorted(sessions.keys()):
        bundles = sessions.get(session_id, [])
        row: Dict[str, Any] = {
            "Session ID": session_id,
            "Questionnaire Count": len(bundles),
        }

        subjects = {bundle.subject for bundle in bundles if bundle.subject}
        if subjects:
            row["Participant References"] = "; ".join(sorted(subjects))

        for bundle in bundles:
            if bundle.authored:
                authored_timestamp = parse_timestamp(bundle.authored)
                meta_label = build_metadata_label(bundle.title, "Authored On")
                row[meta_label] = authored_timestamp if authored_timestamp is not None else bundle.authored
            for answer in bundle.answers:
                label = build_answer_label(answer)

                display_value = answer.display if answer.display is not None else ""
                if label not in row or not row[label]:
                    row[label] = display_value
                else:
                    existing_value = row[label]
                    existing_tokens: List[str]
                    if isinstance(existing_value, str):
                        existing_tokens = [token.strip() for token in existing_value.split(";") if token.strip()]
                    elif isinstance(existing_value, list):
                        existing_tokens = [str(token) for token in existing_value]
                    else:
                        existing_tokens = [str(existing_value)]

                    candidate = str(display_value)
                    if candidate and candidate not in existing_tokens:
                        existing_tokens.append(candidate)
                        row[label] = "; ".join(existing_tokens)

        rows.append(row)

    summary_df = pd.DataFrame(rows)
    if not summary_df.empty:
        summary_df = summary_df.sort_values("Session ID").reset_index(drop=True)
    return summary_df


def write_excel_report(
    excel_path: Path,
    summary_df: pd.DataFrame,
    sessions: Mapping[str, List[QuestionnaireResponseBundle]],
    question_catalog: Sequence[Mapping[str, Any]],
) -> None:
    excel_path.parent.mkdir(parents=True, exist_ok=True)

    with pd.ExcelWriter(excel_path, engine="xlsxwriter") as writer:
        summary_df.to_excel(writer, sheet_name="Summary", index=False)
        workbook = writer.book
        bold = workbook.add_format({"bold": True})
        wrap = workbook.add_format({"text_wrap": True})
        header_fmt = workbook.add_format({"bold": True, "bg_color": "#F2F5FA"})
        date_fmt = workbook.add_format({"num_format": "yyyy-mm-dd hh:mm"})
        integer_fmt = workbook.add_format({"num_format": "0"})

        summary_sheet = writer.sheets["Summary"]
        summary_sheet.freeze_panes(1, 0)
        summary_sheet.set_row(0, None, header_fmt)
        if not summary_df.empty:
            summary_sheet.autofilter(0, 0, summary_df.shape[0], summary_df.shape[1] - 1)

        date_columns = [col for col in summary_df.columns if pd.api.types.is_datetime64_any_dtype(summary_df[col])]
        for idx, column in enumerate(summary_df.columns):
            series = summary_df[column]
            if column in date_columns:
                summary_sheet.set_column(idx, idx, 22, date_fmt)
            elif pd.api.types.is_integer_dtype(series) or pd.api.types.is_float_dtype(series):
                summary_sheet.set_column(idx, idx, 18, integer_fmt)
            else:
                col_values = series.astype(str).replace({"nan": ""})
                max_content = max([len(column)] + [len(v) for v in col_values]) if not col_values.empty else len(column)
                width = min(60, max(12, max_content + 2))
                fmt = wrap if pd.api.types.is_object_dtype(series) else None
                summary_sheet.set_column(idx, idx, width, fmt)

        used_sheet_names: Dict[str, int] = {}
        for session_id in sorted(sessions.keys()):
            base_name = session_id[:31] or "Session"
            sheet_name = base_name
            counter = 1
            while sheet_name in used_sheet_names:
                suffix = f"_{counter}"
                sheet_name = f"{base_name[:31 - len(suffix)]}{suffix}"
                counter += 1
            used_sheet_names[sheet_name] = 1

            worksheet = workbook.add_worksheet(sheet_name)
            writer.sheets[sheet_name] = worksheet

            bundles = sessions.get(session_id, [])

            row = 0
            worksheet.write(row, 0, "Session ID", bold)
            worksheet.write(row, 1, session_id)
            row += 1

            participants = sorted({bundle.subject for bundle in bundles if bundle.subject})
            if participants:
                worksheet.write(row, 0, "Participants", bold)
                worksheet.write(row, 1, ", ".join(participants))
                row += 1

            worksheet.write(row, 0, "Questionnaires", bold)
            worksheet.write(row, 1, str(len(bundles)))
            row += 2

            for bundle in bundles:
                worksheet.write(row, 0, bundle.title, bold)
                if bundle.authored:
                    worksheet.write(row, 1, "Authored", bold)
                    authored_ts = parse_timestamp(bundle.authored)
                    if authored_ts is not None:
                        worksheet.write_datetime(row, 2, authored_ts, date_fmt)
                    else:
                        worksheet.write(row, 2, bundle.authored)
                row += 1

                if bundle.answers:
                    data = [
                        {
                            "LinkId": answer.link_id,
                            "Question": answer.question,
                            "Section": answer.section,
                            "Response": answer.display,
                        }
                        for answer in bundle.answers
                    ]
                    df = pd.DataFrame(data)
                    df.to_excel(writer, sheet_name=sheet_name, startrow=row, startcol=0, index=False)
                    worksheet.set_row(row, None, header_fmt)

                    for col_idx, column in enumerate(df.columns):
                        series = df[column]
                        if pd.api.types.is_datetime64_any_dtype(series):
                            worksheet.set_column(col_idx, col_idx, 22, date_fmt)
                            continue
                        if pd.api.types.is_numeric_dtype(series):
                            worksheet.set_column(col_idx, col_idx, 14, integer_fmt)
                            continue
                        values = series.astype(str).replace({"nan": ""})
                        max_content = max([len(column)] + [len(v) for v in values]) if not values.empty else len(column)
                        width = min(60, max(12, max_content + 2))
                        fmt = wrap if column in {"Section", "Question", "Response"} else None
                        worksheet.set_column(col_idx, col_idx, width, fmt)
                    row += len(df) + 2
                else:
                    worksheet.write(row, 0, "No answers found.")
                    row += 2

        if question_catalog:
            catalog_df = pd.DataFrame(question_catalog)
            catalog_df = catalog_df.sort_values(["Questionnaire", "Section", "Question"], na_position="last").reset_index(drop=True)
            catalog_df.to_excel(writer, sheet_name="Question Catalog", index=False)
            catalog_sheet = writer.sheets["Question Catalog"]
            catalog_sheet.freeze_panes(1, 0)
            catalog_sheet.set_row(0, None, header_fmt)
            if not catalog_df.empty:
                catalog_sheet.autofilter(0, 0, catalog_df.shape[0], catalog_df.shape[1] - 1)
            for idx, column in enumerate(catalog_df.columns):
                series = catalog_df[column].fillna("")
                max_content = max([len(column)] + [len(str(v)) for v in series]) if not series.empty else len(column)
                width = min(60, max(12, max_content + 2))
                fmt = wrap if column in {"Section", "Question", "Possible Choices"} else None
                catalog_sheet.set_column(idx, idx, width, fmt)


def write_csv_summary(csv_path: Path, summary_df: pd.DataFrame) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    summary_df.to_csv(csv_path, index=False)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate ENGAGE-HF session reports.")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path.cwd(),
        help="Root directory containing questionnaire JSON files and response folders.",
    )
    parser.add_argument(
        "--excel",
        type=Path,
        default=DEFAULT_OUTPUT_DIR / "session_reports.xlsx",
        help="Path for the generated Excel workbook.",
    )
    parser.add_argument(
        "--csv",
        type=Path,
        default=DEFAULT_OUTPUT_DIR / "session_summary.csv",
        help="Path for the generated CSV summary.",
    )
    args = parser.parse_args()

    root = args.root.resolve()
    excel_path = args.excel if args.excel.is_absolute() else (root / args.excel)
    csv_path = args.csv if args.csv.is_absolute() else (root / args.csv)

    sessions, question_catalog = collect_questionnaire_data(root)

    if not sessions:
        raise SystemExit("No questionnaire responses found under the specified root directory.")

    summary_df = build_summary_dataframe(sessions)

    write_excel_report(excel_path, summary_df, sessions, question_catalog)
    write_csv_summary(csv_path, summary_df)

    print(f"Written Excel report to {excel_path}")
    print(f"Written CSV summary to {csv_path}")


if __name__ == "__main__":
    main()
