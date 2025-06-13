//
//  ServiceState.swift
//  ENGAGE-HF-AI-Voice
//
//  Created by Nikolai Madlener on 28.05.25.
//

import Vapor

actor ServiceState {
    private var services: [QuestionnaireService.Type]
    private var currentIndex: Int
    
    init(services: [QuestionnaireService.Type]) {
        self.services = services
        self.currentIndex = 0
    }
    
    var current: QuestionnaireService.Type {
        services[currentIndex]
    }
    
    var hasNext: Bool {
        currentIndex < services.count - 1
    }
    
    func next() -> QuestionnaireService.Type? {
        guard hasNext else { return nil }
        currentIndex += 1
        return current
    }
    
    func reset() {
        currentIndex = 0
    }
    
    func initializeCurrentService(phoneNumber: String, logger: Logger) async {
        for (index, serviceType) in services.enumerated() {
            if await serviceType.unansweredQuestionsLeft(phoneNumber: phoneNumber, logger: logger) {
                currentIndex = index
                break
            }
        }
    }
}
