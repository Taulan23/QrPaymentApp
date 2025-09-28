//
//  QRPaymentsViewModel.swift
//  QRPayments
//
//  Created by QR Payments Team on 25/09/2025.
//

import SwiftUI
import PhotosUI
import UIKit
import Combine

class QRPaymentsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var exchangeRate: Double? = nil
    @Published var rmbAmount: Double? = nil
    @Published var rubAmount: Double? = nil
    @Published var contractNumberEnabled: Bool = false
    @Published var contractNumber: String = "22"
    @Published var qrCodeImage: UIImage? = nil
    @Published var qrDisplayText: String? = nil
    @Published var currentQRFormat: QRFormat = .spb
    
    // MARK: - Private Properties
    private let qrGenerator = QRCodeGenerator()
    private let currencyCalculator = CurrencyCalculator()
    private let spbQRFormat = SPBQRFormat()
    
    // Кэш для QR кодов для улучшения производительности (бесконечный размер)
    private var qrCodeCache: [String: UIImage] = [:]
    
    // Статистика кэша для мониторинга
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var totalCacheSize: Int = 0
    
    // Флаг для предотвращения повторных вызовов генерации
    private var isGeneratingQR = false
    
    // Флаг для предотвращения повторных сохранений
    @Published var isSaving = false
    
    // Банковские реквизиты (обновлены согласно PDF)
    private let bankName = "ИНДИВИДУАЛЬНЫЙ ПРЕДПРИНИМАТЕЛЬ КОНОНЕНКО РОБЕРТ АЛЕКСАНДРОВИЧ"
    private let inn = "270395244282"
    private let accountNumber = "40802810100004257312"
    private let ogrn = "323237500046362"
    private let bank = "АО «ТБанк»"
    private let bik = "044525974"
    private let bankInn = "7710140679"
    private let corrAccount = "30101810145250000974"
    private let legalAddress = "127287, г. Москва, ул. Хуторская 2-я, д. 38А, стр. 26"
    
    // MARK: - Computed Properties
    var currentFormatDescription: String {
        switch currentQRFormat {
        case .spb:
            return "Стандартный СБП (рекомендуется)\nСовместим со всеми банками через СБП"
        case .bank:
            return "Банковский формат\nСтандартный банковский платежный QR-код"
        case .simple:
            return "Простой текст\nУпрощенный формат для резервных случаев"
        }
    }
    
    // MARK: - Initialization
    init() {
        setupBindings()
    }
    
    // MARK: - Private Methods
    private func setupBindings() {
        // Автоматическое обновление при изменении данных
        Publishers.CombineLatest4($exchangeRate, $rmbAmount, $rubAmount, $contractNumberEnabled)
            .combineLatest($contractNumber)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.calculateAndUpdateQR()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    func calculateAndUpdateQR() {
        guard let exchangeRate = exchangeRate,
              let rmbAmount = rmbAmount,
              exchangeRate > 0,
              rmbAmount > 0 else {
            clearQRCode()
            return
        }
        
        // Рассчитываем сумму в рублях
        let calculatedRubAmount = rmbAmount * exchangeRate
        
        // Обновляем поле суммы в рублях только если оно пустое
        if rubAmount == nil {
            DispatchQueue.main.async {
                self.rubAmount = calculatedRubAmount
            }
        }
        
        // Используем актуальную сумму
        let finalRubAmount = rubAmount ?? calculatedRubAmount
        
        // Обновляем отображение
        updateQRCodeDisplay(rmbAmount: rmbAmount, rubAmount: finalRubAmount)
        
        // Генерируем QR-код
        generateQRCodeForAmount(rmbAmount: rmbAmount, rubAmount: finalRubAmount)
    }
    
    func calculateAndUpdateQRFromRub() {
        guard let rubAmount = rubAmount,
              rubAmount > 0 else {
            clearQRCode()
            return
        }
        
        var finalRmbAmount = rmbAmount ?? 0
        var finalExchangeRate = exchangeRate ?? 11.65
        
        if finalRmbAmount > 0 {
            // Есть RMB и рубли - пересчитываем курс
            finalExchangeRate = rubAmount / finalRmbAmount
            DispatchQueue.main.async {
                self.exchangeRate = finalExchangeRate
            }
        } else if finalExchangeRate > 0 {
            // Есть курс и рубли - пересчитываем RMB
            finalRmbAmount = rubAmount / finalExchangeRate
            DispatchQueue.main.async {
                self.rmbAmount = finalRmbAmount
            }
        } else {
            clearQRCode()
            return
        }
        
        if finalRmbAmount > 0 && rubAmount > 0 {
            updateQRCodeDisplay(rmbAmount: finalRmbAmount, rubAmount: rubAmount)
            generateQRCodeForAmount(rmbAmount: finalRmbAmount, rubAmount: rubAmount)
        } else {
            clearQRCode()
        }
    }
    
    private func updateQRCodeDisplay(rmbAmount: Double, rubAmount: Double) {
        DispatchQueue.main.async {
            self.qrDisplayText = "\(String(format: "%.2f", rmbAmount)) rmb / \(String(format: "%.2f", rubAmount)) руб."
        }
    }
    
    private func generateQRCodeForAmount(rmbAmount: Double, rubAmount: Double) {
        // Проверяем валидность входных данных
        guard rmbAmount > 0 && rubAmount > 0 && rmbAmount.isFinite && rubAmount.isFinite else {
            clearQRCode()
            return
        }
        
        // Проверяем, что генерация уже не идет
        guard !isGeneratingQR else {
            print("⚠️ Генерация QR-кода уже выполняется, пропускаем")
            return
        }
        
        let qrText = buildQRCodeText(rmbAmount: rmbAmount, rubAmount: rubAmount)
        
        // Проверяем, что текст QR-кода не пустой
        guard !qrText.isEmpty else {
            clearQRCode()
            return
        }
        
        // Проверяем кэш для оптимизации
        let cacheKey = "\(rmbAmount)_\(rubAmount)_\(currentQRFormat)"
        if let cachedImage = qrCodeCache[cacheKey] {
            cacheHits += 1
            print("🎯 Кэш попадание! Всего попаданий: \(cacheHits), промахов: \(cacheMisses)")
            DispatchQueue.main.async { [weak self] in
                self?.qrCodeImage = cachedImage
                self?.qrDisplayText = qrText
            }
            return
        }
        
        cacheMisses += 1
        print("💾 Кэш промах! Всего попаданий: \(cacheHits), промахов: \(cacheMisses)")
        
        // Устанавливаем флаг генерации
        isGeneratingQR = true
        
        // Генерируем QR код в фоновом потоке
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Создаем тексты для отображения на QR-коде
            let topText = "\(String(format: "%.0f", rmbAmount)) rmb / \(String(format: "%.0f", rubAmount)) руб."
            let bottomText = "Курс: \(String(format: "%.2f", rmbAmount > 0 ? rubAmount / rmbAmount : 0))"
            
            self.qrGenerator.generateQRCodeWithText(
                qrText: qrText,
                topText: topText,
                bottomText: bottomText
            ) { image in
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    // Сбрасываем флаг генерации
                    self.isGeneratingQR = false
                    
                    if let image = image {
                        // Сохраняем в кэш только если изображение валидно
                        self.qrCodeCache[cacheKey] = image
                        
                        // Обновляем статистику размера кэша
                        let imageSize = Int(image.size.width * image.size.height * 4) // Примерный размер в байтах
                        self.totalCacheSize += imageSize
                        
                        print("💾 QR-код сохранен в кэш. Размер кэша: \(self.qrCodeCache.count) элементов, ~\(self.totalCacheSize / 1024) KB")
                        
                        self.qrCodeImage = image
                        self.qrDisplayText = qrText
                    } else {
                        // Если генерация не удалась, очищаем QR-код
                        self.clearQRCode()
                    }
                }
            }
        }
    }
    
    
    private func buildQRCodeText(rmbAmount: Double, rubAmount: Double) -> String {
        let purpose = contractNumberEnabled 
            ? "Оплата по договору \(contractNumber). Услуга оплаты товара \(formatNumber(rmbAmount)) RMB"
            : "Услуга оплаты товара \(formatNumber(rmbAmount)) RMB"
        
        switch currentQRFormat {
        case .spb:
            return spbQRFormat.buildSPBQrCode(
                rubAmount: rubAmount,
                purpose: purpose,
                bankName: bankName,
                accountNumber: accountNumber,
                bank: bank,
                bik: bik,
                corrAccount: corrAccount,
                inn: inn,
                ogrn: ogrn,
                bankInn: bankInn,
                legalAddress: legalAddress
            )
        case .bank:
            return spbQRFormat.buildBankPaymentQrCode(
                rubAmount: rubAmount,
                purpose: purpose,
                bankName: bankName,
                accountNumber: accountNumber,
                bank: bank,
                bik: bik,
                corrAccount: corrAccount,
                inn: inn,
                ogrn: ogrn,
                bankInn: bankInn,
                legalAddress: legalAddress
            )
        case .simple:
            return "СБП: \(formatNumber(rubAmount)) руб. - \(purpose) - Получатель: \(bankName) (\(inn)) - Счет: \(accountNumber)"
        }
    }
    
    private func formatNumber(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: number)) ?? "\(Int(number))"
    }
    
    func toggleQRFormat() {
        currentQRFormat = currentQRFormat.next()
        calculateAndUpdateQR()
    }
    
    func clearQRCode() {
        DispatchQueue.main.async {
            self.qrCodeImage = nil
            self.qrDisplayText = "Введите корректные данные"
        }
    }
    
    // MARK: - Cache Management
    func getCacheStatistics() -> (hits: Int, misses: Int, size: Int, count: Int) {
        return (cacheHits, cacheMisses, totalCacheSize, qrCodeCache.count)
    }
    
    func clearCache() {
        qrCodeCache.removeAll()
        cacheHits = 0
        cacheMisses = 0
        totalCacheSize = 0
        print("🗑️ Кэш QR-кодов очищен")
    }
    
    func preloadCommonQRCodes() {
        // Предзагрузка популярных комбинаций для ускорения работы
        let commonRates = [11.0, 11.5, 12.0, 12.25, 12.5, 13.0]
        let commonAmounts = [100.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0]
        
        print("🚀 Начинаем предзагрузку популярных QR-кодов...")
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            
            for rate in commonRates {
                for amount in commonAmounts {
                    let rubAmount = amount * rate
                    let qrText = self.buildQRCodeText(rmbAmount: amount, rubAmount: rubAmount)
                    
                    if !qrText.isEmpty {
                        let topText = "\(String(format: "%.0f", amount)) rmb / \(String(format: "%.0f", rubAmount)) руб."
                        let bottomText = "Курс: \(String(format: "%.2f", rate))"
                        
                        self.qrGenerator.generateQRCodeWithText(
                            qrText: qrText,
                            topText: topText,
                            bottomText: bottomText
                        ) { image in
                            if let image = image {
                                let cacheKey = "\(amount)_\(rubAmount)_\(self.currentQRFormat)"
                                self.qrCodeCache[cacheKey] = image
                                
                                let imageSize = Int(image.size.width * image.size.height * 4)
                                self.totalCacheSize += imageSize
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                print("✅ Предзагрузка завершена. Кэш содержит \(self.qrCodeCache.count) элементов")
            }
        }
    }
    
    func saveQRCode() {
        guard !isSaving else { return }
        guard let qrImage = qrCodeImage else {
            showAlert(title: "Ошибка", message: "Нет QR-кода для сохранения")
            return
        }
        
        isSaving = true
        
        // Добавляем таймаут на случай, если callback не сработает
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            if self.isSaving {
                self.isSaving = false
                self.showAlert(title: "Ошибка", message: "Таймаут сохранения. Попробуйте еще раз.")
            }
        }
        
        // Простая проверка разрешений
        if PHPhotoLibrary.authorizationStatus() == .authorized {
            UIImageWriteToSavedPhotosAlbum(qrImage, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        UIImageWriteToSavedPhotosAlbum(qrImage, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
                    } else {
                        self.isSaving = false
                        self.showAlert(title: "Ошибка", message: "Нет доступа к галерее")
                    }
                }
            }
        }
    }
    
    
    
    @objc private func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.isSaving = false
            
            if let error = error {
                print("❌ Ошибка сохранения: \(error.localizedDescription)")
                self.showAlert(title: "Ошибка", message: "Не удалось сохранить: \(error.localizedDescription)")
            } else {
                print("✅ QR-код успешно сохранен!")
                self.showAlert(title: "Успех", message: "QR-код сохранен в галерею")
            }
        }
    }
    
    // Альтернативный способ сохранения через PhotosUI
    func saveQRCodeAlternative() {
        guard !isSaving else { return }
        guard let qrImage = qrCodeImage else {
            showAlert(title: "Ошибка", message: "Нет QR-кода для сохранения")
            return
        }
        
        isSaving = true
        
        // Используем PHPhotoLibrary для сохранения
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: qrImage)
        }) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSaving = false
                
                if success {
                    self.showAlert(title: "Успех", message: "QR-код сохранен в галерею")
                } else {
                    let errorMessage = error?.localizedDescription ?? "Неизвестная ошибка"
                    self.showAlert(title: "Ошибка", message: "Не удалось сохранить: \(errorMessage)")
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                  let rootViewController = window.rootViewController else {
                return
            }
            
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            rootViewController.present(alert, animated: true)
        }
    }
    
    func loadSavedData() {
        // Загружаем сохраненные данные из UserDefaults
        if let savedExchangeRate = UserDefaults.standard.object(forKey: "exchangeRate") as? Double {
            exchangeRate = savedExchangeRate
        }
        if let savedRmbAmount = UserDefaults.standard.object(forKey: "rmbAmount") as? Double {
            rmbAmount = savedRmbAmount
        }
        if let savedRubAmount = UserDefaults.standard.object(forKey: "rubAmount") as? Double {
            rubAmount = savedRubAmount
        }
        contractNumberEnabled = UserDefaults.standard.bool(forKey: "contractNumberEnabled")
        if let savedContractNumber = UserDefaults.standard.string(forKey: "contractNumber") {
            contractNumber = savedContractNumber
        }
        
        // Загружаем статистику кэша
        cacheHits = UserDefaults.standard.integer(forKey: "cacheHits")
        cacheMisses = UserDefaults.standard.integer(forKey: "cacheMisses")
        
        // Запускаем предзагрузку популярных QR-кодов
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.preloadCommonQRCodes()
        }
        
        // Сохраняем данные при изменении
        $exchangeRate.sink { [weak self] value in
            if let value = value {
                UserDefaults.standard.set(value, forKey: "exchangeRate")
            }
        }.store(in: &cancellables)
        
        $rmbAmount.sink { [weak self] value in
            if let value = value {
                UserDefaults.standard.set(value, forKey: "rmbAmount")
            }
        }.store(in: &cancellables)
        
        $rubAmount.sink { [weak self] value in
            if let value = value {
                UserDefaults.standard.set(value, forKey: "rubAmount")
            }
        }.store(in: &cancellables)
        
        $contractNumberEnabled.sink { [weak self] value in
            UserDefaults.standard.set(value, forKey: "contractNumberEnabled")
        }.store(in: &cancellables)
        
        $contractNumber.sink { [weak self] value in
            UserDefaults.standard.set(value, forKey: "contractNumber")
        }.store(in: &cancellables)
        
        // Сохраняем статистику кэша при изменении
        Timer.publish(every: 30.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                UserDefaults.standard.set(self.cacheHits, forKey: "cacheHits")
                UserDefaults.standard.set(self.cacheMisses, forKey: "cacheMisses")
            }
            .store(in: &cancellables)
    }
}

// MARK: - QR Format Enum
enum QRFormat: CaseIterable {
    case spb
    case bank
    case simple
    
    func next() -> QRFormat {
        let allCases = QRFormat.allCases
        let currentIndex = allCases.firstIndex(of: self) ?? 0
        let nextIndex = (currentIndex + 1) % allCases.count
        return allCases[nextIndex]
    }
}
