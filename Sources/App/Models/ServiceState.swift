//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//


import Vapor

actor ServiceState {
    private var services: [QuestionnaireService.Type]
    private var currentIndex: Int
    
    var current: QuestionnaireService.Type {
        services[currentIndex]
    }
    
    var hasNext: Bool {
        currentIndex < services.count - 1
    }
    
    
    init(services: [QuestionnaireService.Type]) {
        self.services = services
        self.currentIndex = 0
    }
    
    func next() -> QuestionnaireService.Type? {
        guard hasNext else {
            return nil
        }
        currentIndex += 1
        return current
    }
    
    func reset() {
        currentIndex = 0
    }
    
    func initializeCurrentService(phoneNumber: String, logger: Logger) async {
        for (index, serviceType) in services.enumerated() where await serviceType.unansweredQuestionsLeft() {
            currentIndex = index
            break
        }
    }
}
