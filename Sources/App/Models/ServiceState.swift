//
// This source file is part of the ENGAGE-HF-AI-Voice open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Vapor


actor ServiceState {
    private var services: [any QuestionnaireService]
    private var currentIndex: Int
    private var totalSectionCount: Int?
    private var firstServiceIndex: Int?
    
    var current: any QuestionnaireService {
        services[currentIndex]
    }
    
    var hasNext: Bool {
        currentIndex < services.count - 1
    }
    
    
    init(services: [any QuestionnaireService]) {
        self.services = services
        self.currentIndex = 0
        self.totalSectionCount = nil
        self.firstServiceIndex = nil
    }
    
    func next() -> (any QuestionnaireService)? {
        guard hasNext else {
            return nil
        }
        currentIndex += 1
        return current
    }
    
    func reset() {
        currentIndex = 0
    }
    
    func initializeCurrentService() async -> Bool {
        // Find all services with unanswered questions
        var servicesWithUnansweredQuestions: [Int] = []
        for (index, service) in services.enumerated() {
            if await service.unansweredQuestionsLeft() {
                servicesWithUnansweredQuestions.append(index)
            }
        }
        
        if servicesWithUnansweredQuestions.isEmpty {
            // No service has unanswered questions (i.e. all services have all questions answered already)
            return false
        }
        
        // Set the total section count based on services with unanswered questions
        // This remains constant throughout the session
        totalSectionCount = servicesWithUnansweredQuestions.count
        firstServiceIndex = servicesWithUnansweredQuestions.first
        
        // Set current index to the first service with unanswered questions
        currentIndex = servicesWithUnansweredQuestions.first!
        return true
    }
    
    func getFeedback(phoneNumber: String, logger: Logger) async throws -> String {
        guard let vitalSignsService = getVitalSignsService(),
              let kccq12Service = getKCCQ12Service(),
              let q17Service = getQ17Service() else {
            throw Abort(.internalServerError, reason: "Service instances not available")
        }
        
        let feedbackService = await FeedbackService(
            phoneNumber: phoneNumber,
            logger: logger,
            vitalSignsService: vitalSignsService,
            kccq12Service: kccq12Service,
            q17Service: q17Service
        )
        return await feedbackService.feedback() ?? "No feedback available."
    }
    
    // MARK: - Service Access Methods
    
    func getVitalSignsService() -> VitalSignsService? {
        services.first { $0 is VitalSignsService } as? VitalSignsService
    }
    
    func getKCCQ12Service() -> KCCQ12Service? {
        services.first { $0 is KCCQ12Service } as? KCCQ12Service
    }
    
    func getQ17Service() -> Q17Service? {
        services.first { $0 is Q17Service } as? Q17Service
    }
    
    /// Get the current section number (1-indexed) and total sections
    /// - Returns: A tuple containing (currentSectionNumber, totalSectionCount)
    func getSectionProgress() -> (currentSectionNumber: Int, totalSectionCount: Int) {
        let total = totalSectionCount ?? services.count
        let first = firstServiceIndex ?? 0
        
        // Calculate the current section number relative to the first service with unanswered questions
        // For example, if we start at service index 1 (second service), that becomes section 1 of N
        let current = currentIndex - first + 1
        
        return (currentSectionNumber: current, totalSectionCount: total)
    }
}
