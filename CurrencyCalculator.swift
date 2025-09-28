//
//  CurrencyCalculator.swift
//  QRPayments
//
//  Created by QR Payments Team on 25/09/2025.
//

import Foundation

class CurrencyCalculator {
    
    // MARK: - Public Methods
    
    /// Рассчитывает сумму в рублях на основе курса и суммы RMB
    /// - Parameters:
    ///   - rmbAmount: Сумма в китайских юанях
    ///   - exchangeRate: Курс валют (RMB к RUB)
    /// - Returns: Сумма в рублях
    func calculateRubAmount(rmbAmount: Double, exchangeRate: Double) -> Double {
        return rmbAmount * exchangeRate
    }
    
    /// Рассчитывает сумму в RMB на основе курса и суммы в рублях
    /// - Parameters:
    ///   - rubAmount: Сумма в рублях
    ///   - exchangeRate: Курс валют (RMB к RUB)
    /// - Returns: Сумма в китайских юанях
    func calculateRmbAmount(rubAmount: Double, exchangeRate: Double) -> Double {
        return rubAmount / exchangeRate
    }
    
    /// Рассчитывает курс валют на основе сумм в разных валютах
    /// - Parameters:
    ///   - rmbAmount: Сумма в китайских юанях
    ///   - rubAmount: Сумма в рублях
    /// - Returns: Курс валют (RMB к RUB)
    func calculateExchangeRate(rmbAmount: Double, rubAmount: Double) -> Double {
        return rubAmount / rmbAmount
    }
    
    /// Валидирует введенные данные
    /// - Parameters:
    ///   - exchangeRate: Курс валют
    ///   - rmbAmount: Сумма в китайских юанях
    ///   - rubAmount: Сумма в рублях
    /// - Returns: Результат валидации
    func validateInput(exchangeRate: Double?, rmbAmount: Double?, rubAmount: Double?) -> ValidationResult {
        var errors: [String] = []
        
        if let rate = exchangeRate, rate <= 0 {
            errors.append("Курс должен быть больше нуля")
        }
        
        if let rmb = rmbAmount, rmb <= 0 {
            errors.append("Сумма RMB должна быть больше нуля")
        }
        
        if let rub = rubAmount, rub <= 0 {
            errors.append("Сумма в рублях должна быть больше нуля")
        }
        
        // Проверяем, что хотя бы одна сумма введена
        if rmbAmount == nil && rubAmount == nil {
            errors.append("Введите хотя бы одну сумму (RMB или рубли)")
        }
        
        // Проверяем разумные пределы
        if let rate = exchangeRate, rate > 1000 {
            errors.append("Курс слишком большой. Максимум 1000")
        }
        
        if let rmb = rmbAmount, rmb > 1000000 {
            errors.append("Сумма RMB слишком большая. Максимум 1,000,000")
        }
        
        if let rub = rubAmount, rub > 1000000 {
            errors.append("Сумма в рублях слишком большая. Максимум 1,000,000")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
    
    /// Форматирует число для отображения
    /// - Parameter number: Число для форматирования
    /// - Returns: Отформатированная строка
    func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
    
    /// Форматирует число для QR-кода (без дробной части)
    /// - Parameter number: Число для форматирования
    /// - Returns: Отформатированная строка без дробной части
    func formatNumberForQR(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(Int(number))"
    }
}

// MARK: - Validation Result
struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    
    var errorMessage: String {
        return errors.joined(separator: "\n")
    }
}
