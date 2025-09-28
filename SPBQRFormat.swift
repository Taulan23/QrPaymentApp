//
//  SPBQRFormat.swift
//  QRPayments
//
//  Created by QR Payments Team on 25/09/2025.
//

import Foundation

class SPBQRFormat {
    
    // MARK: - Public Methods
    
    /// Генерирует стандартный QR-код СБП (Система быстрых платежей)
    /// - Parameters:
    ///   - rubAmount: Сумма в рублях
    ///   - purpose: Назначение платежа
    ///   - bankName: Название банка/получателя
    ///   - accountNumber: Номер расчетного счета
    ///   - bank: Название банка
    ///   - bik: БИК банка
    ///   - corrAccount: Корреспондентский счет
    ///   - inn: ИНН получателя
    ///   - ogrn: ОГРН/ОГРНИП
    ///   - bankInn: ИНН банка
    ///   - legalAddress: Юридический адрес банка
    /// - Returns: Текст для QR-кода в формате СБП
    func buildSPBQrCode(rubAmount: Double, 
                       purpose: String, 
                       bankName: String, 
                       accountNumber: String, 
                       bank: String, 
                       bik: String, 
                       corrAccount: String, 
                       inn: String,
                       ogrn: String,
                       bankInn: String,
                       legalAddress: String) -> String {
        
        // Формат СБП: ST00012|Name=Имя|PersonalAcc=Счет|BankName=Банк|BIC=БИК|CorrespAcc=КоррСчет|PayeeINN=ИНН|Sum=Сумма|Purpose=Назначение
        let sumInKopecks = Int(rubAmount * 100) // Сумма в копейках
        
        return "ST00012|" +
               "Name=\(sanitizeString(bankName))|" +
               "PersonalAcc=\(accountNumber)|" +
               "BankName=\(sanitizeString(bank))|" +
               "BIC=\(bik)|" +
               "CorrespAcc=\(corrAccount)|" +
               "PayeeINN=\(inn)|" +
               "Sum=\(sumInKopecks)|" +
               "Purpose=\(sanitizeString(purpose))"
    }
    
    /// Генерирует стандартный банковский платежный QR-код
    /// - Parameters:
    ///   - rubAmount: Сумма в рублях
    ///   - purpose: Назначение платежа
    ///   - bankName: Название банка/получателя
    ///   - accountNumber: Номер расчетного счета
    ///   - bank: Название банка
    ///   - bik: БИК банка
    ///   - corrAccount: Корреспондентский счет
    ///   - inn: ИНН получателя
    ///   - ogrn: ОГРН/ОГРНИП
    ///   - bankInn: ИНН банка
    ///   - legalAddress: Юридический адрес банка
    /// - Returns: Текст для QR-кода в банковском формате
    func buildBankPaymentQrCode(rubAmount: Double, 
                               purpose: String, 
                               bankName: String, 
                               accountNumber: String, 
                               bank: String, 
                               bik: String, 
                               corrAccount: String, 
                               inn: String,
                               ogrn: String,
                               bankInn: String,
                               legalAddress: String) -> String {
        
        // Структура: BANK|ИНН|Счет|БИК|КоррСчет|Сумма|Назначение|Получатель
        let sumInKopecks = Int(rubAmount * 100) // Сумма в копейках
        
        return "BANK|" +
               "\(inn)|" +
               "\(accountNumber)|" +
               "\(bik)|" +
               "\(corrAccount)|" +
               "\(sumInKopecks)|" +
               "\(sanitizeString(purpose))|" +
               "\(sanitizeString(bankName))"
    }
    
    /// Генерирует простой текстовый QR-код для СБП
    /// - Parameters:
    ///   - rubAmount: Сумма в рублях
    ///   - purpose: Назначение платежа
    ///   - bankName: Название банка/получателя
    ///   - accountNumber: Номер расчетного счета
    ///   - inn: ИНН получателя
    /// - Returns: Простой текстовый QR-код
    func buildSimpleSPBQrCode(rubAmount: Double, 
                            purpose: String, 
                            bankName: String, 
                            accountNumber: String, 
                            inn: String) -> String {
        
        let formattedAmount = formatNumberForQR(rubAmount)
        
        return "СБП: \(formattedAmount) руб. - \(purpose) - Получатель: \(bankName) (\(inn)) - Счет: \(accountNumber)"
    }
    
    // MARK: - Private Methods
    
    /// Очищает строку от символов, которые могут нарушить формат QR-кода
    /// - Parameter string: Исходная строка
    /// - Returns: Очищенная строка
    private func sanitizeString(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "|", with: "")
            .replacingOccurrences(of: "\\", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Форматирует число для QR-кода
    /// - Parameter number: Число для форматирования
    /// - Returns: Отформатированная строка
    private func formatNumberForQR(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(Int(number))"
    }
}
