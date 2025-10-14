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
    
    var current: any QuestionnaireService {
        services[currentIndex]
    }
    
    var hasNext: Bool {
        currentIndex < services.count - 1
    }
    
    
    init(services: [any QuestionnaireService]) {
        self.services = services
        self.currentIndex = 0
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
        for (index, service) in services.enumerated() where await service.unansweredQuestionsLeft() {
            currentIndex = index
            return true  // Found a service with unanswered questions
        }
        
        // No service has unanswered questions (i.e. all services have all questions answered already)
        return false
    }
    
    func getFeedback(phoneNumber: String, logger: Logger) async throws -> String {
        guard let vitalSignsService = getVitalSignsService(),
              let kccq12Service = getKCCQ12Service(),
              let q17Service = getQ17Service() else {
            logger.error("Failed to get all service instances while trying to generate a feedback statement.")
            throw Abort(.internalServerError, reason: "Service instances not available")
        }
        
        let feedbackService = await FeedbackService(
            phoneNumber: phoneNumber,
            logger: logger,
            vitalSignsService: vitalSignsService,
            kccq12Service: kccq12Service,
            q17Service: q17Service
        )
        
        guard let feedback = await feedbackService.feedback() else {
            logger.error("FeedbackService wasn't able to generate a feedback statement.")
            return "No feedback available."
        }
        return feedback
    }
        
    func getVitalSignsService() -> VitalSignsService? {
        services.first { $0 is VitalSignsService } as? VitalSignsService
    }
    
    func getKCCQ12Service() -> KCCQ12Service? {
        services.first { $0 is KCCQ12Service } as? KCCQ12Service
    }
    
    func getQ17Service() -> Q17Service? {
        services.first { $0 is Q17Service } as? Q17Service
    }
}
