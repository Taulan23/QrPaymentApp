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
    @Published var paymentPurpose: String? = nil
    @Published var currentQRFormat: QRFormat = .spb
    
    // MARK: - Private Properties
    private let qrGenerator = QRCodeGenerator()
    private let currencyCalculator = CurrencyCalculator()
    private let spbQRFormat = SPBQRFormat()
    
    // Кэш для QR кодов для улучшения производительности (максимум 50 элементов)
    private var qrCodeCache: [String: UIImage] = [:]
    private var cacheAccessOrder: [String] = [] // Для LRU кэша
    private let maxCacheSize = 50 // Максимальное количество элементов в кэше
    
    // Статистика кэша для мониторинга
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0
    private var totalCacheSize: Int = 0
    
    // Флаг для предотвращения повторных вызовов генерации
    private var isGeneratingQR = false
    
    // Флаг для предотвращения повторных сохранений
    @Published var isSaving = false
    
    // Отслеживание последнего измененного поля для правильных расчетов
    private var lastEditedField: EditedField = .none
    private var isUpdatingProgrammatically = false
    
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
        // Отслеживаем изменения курса валют
        $exchangeRate
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self, !self.isUpdatingProgrammatically else { return }
                self.lastEditedField = .exchangeRate
            }
            .store(in: &cancellables)
        
        // Отслеживаем изменения RMB
        $rmbAmount
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self, !self.isUpdatingProgrammatically else { return }
                self.lastEditedField = .rmbAmount
            }
            .store(in: &cancellables)
        
        // Отслеживаем изменения рублей
        $rubAmount
            .dropFirst()
            .sink { [weak self] _ in
                guard let self = self, !self.isUpdatingProgrammatically else { return }
                self.lastEditedField = .rubAmount
            }
            .store(in: &cancellables)
        
        // Отслеживаем изменения номера договора и его состояния
        Publishers.CombineLatest($contractNumberEnabled, $contractNumber)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                // При изменении договора сразу обновляем назначение платежа
                self?.updatePaymentPurpose()
            }
            .store(in: &cancellables)
        
        // Автоматическое обновление при изменении данных
        // Увеличиваем debounce для лучшей производительности
        Publishers.CombineLatest4($exchangeRate, $rmbAmount, $rubAmount, $contractNumberEnabled)
            .combineLatest($contractNumber)
            .debounce(for: .milliseconds(800), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.calculateAndUpdateQR()
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public Methods
    func calculateAndUpdateQR() {
        // Логика расчетов в зависимости от того, какое поле пользователь редактировал
        var finalExchangeRate: Double?
        var finalRmbAmount: Double?
        var finalRubAmount: Double?
        
        switch lastEditedField {
        case .none:
            // Первый запуск или все поля пустые
            if let rate = exchangeRate, let rmb = rmbAmount, rate > 0, rmb > 0 {
                finalExchangeRate = rate
                finalRmbAmount = rmb
                finalRubAmount = rmb * rate
            } else {
                clearQRCode()
                return
            }
            
        case .exchangeRate:
            // Изменился курс - пересчитываем рубли на основе RMB
            guard let rate = exchangeRate, rate > 0 else {
                clearQRCode()
                return
            }
            
            if let rmb = rmbAmount, rmb > 0 {
                finalExchangeRate = rate
                finalRmbAmount = rmb
                finalRubAmount = rmb * rate
            } else if let rub = rubAmount, rub > 0 {
                // Если есть только рубли, пересчитываем RMB
                finalExchangeRate = rate
                finalRubAmount = rub
                finalRmbAmount = rub / rate
            } else {
                clearQRCode()
                return
            }
            
        case .rmbAmount:
            // Изменилось количество RMB - пересчитываем рубли
            guard let rmb = rmbAmount, rmb > 0 else {
                clearQRCode()
                return
            }
            
            if let rate = exchangeRate, rate > 0 {
                finalExchangeRate = rate
                finalRmbAmount = rmb
                finalRubAmount = rmb * rate
            } else if let rub = rubAmount, rub > 0 {
                // Если есть рубли, пересчитываем курс
                finalRmbAmount = rmb
                finalRubAmount = rub
                finalExchangeRate = rub / rmb
            } else {
                clearQRCode()
                return
            }
            
        case .rubAmount:
            // Изменилась сумма в рублях - пересчитываем RMB
            guard let rub = rubAmount, rub > 0 else {
                clearQRCode()
                return
            }
            
            if let rate = exchangeRate, rate > 0 {
                finalExchangeRate = rate
                finalRubAmount = rub
                finalRmbAmount = rub / rate
            } else if let rmb = rmbAmount, rmb > 0 {
                // Если есть RMB, пересчитываем курс
                finalRmbAmount = rmb
                finalRubAmount = rub
                finalExchangeRate = rub / rmb
            } else {
                clearQRCode()
                return
            }
        }
        
        // Проверяем, что все значения валидны
        guard let rate = finalExchangeRate, let rmb = finalRmbAmount, let rub = finalRubAmount,
              rate > 0, rmb > 0, rub > 0,
              rate.isFinite, rmb.isFinite, rub.isFinite else {
            clearQRCode()
            return
        }
        
        // Обновляем поля программно (чтобы не триггерить повторный расчет)
        isUpdatingProgrammatically = true
        
        if exchangeRate != rate {
            exchangeRate = rate
        }
        if rmbAmount != rmb {
            rmbAmount = rmb
        }
        if rubAmount != rub {
            rubAmount = rub
        }
        
        isUpdatingProgrammatically = false
        
        // Обновляем отображение
        updateQRCodeDisplay(rmbAmount: rmb, rubAmount: rub)
        
        // Генерируем QR-код
        generateQRCodeForAmount(rmbAmount: rmb, rubAmount: rub)
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
    
    private func updatePaymentPurpose() {
        // Обновляем назначение платежа при изменении номера договора
        guard let rmbAmount = rmbAmount, rmbAmount > 0 else { return }
        
        let purpose = contractNumberEnabled 
            ? "Оплата по договору \(contractNumber). Услуга оплаты товара \(formatNumber(rmbAmount)) RMB"
            : "Услуга оплаты товара \(formatNumber(rmbAmount)) RMB"
        
        DispatchQueue.main.async { [weak self] in
            self?.paymentPurpose = purpose
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
            // Обновляем порядок доступа (LRU)
            if let index = cacheAccessOrder.firstIndex(of: cacheKey) {
                cacheAccessOrder.remove(at: index)
            }
            cacheAccessOrder.append(cacheKey)
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
        
        // Генерируем QR код в фоновом потоке с более низким приоритетом для экономии ресурсов
        DispatchQueue.global(qos: .utility).async { [weak self] in
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
                        // Применяем LRU политику: удаляем самый старый элемент, если кэш переполнен
                        if self.qrCodeCache.count >= self.maxCacheSize, let oldestKey = self.cacheAccessOrder.first {
                            if let oldImage = self.qrCodeCache.removeValue(forKey: oldestKey) {
                                let oldSize = Int(oldImage.size.width * oldImage.size.height * 4)
                                self.totalCacheSize -= oldSize
                            }
                            self.cacheAccessOrder.removeFirst()
                            print("🗑️ Удален старый элемент из кэша (LRU)")
                        }
                        
                        // Сохраняем в кэш только если изображение валидно
                        self.qrCodeCache[cacheKey] = image
                        self.cacheAccessOrder.append(cacheKey)
                        
                        // Обновляем статистику размера кэша
                        let imageSize = Int(image.size.width * image.size.height * 4) // Примерный размер в байтах
                        self.totalCacheSize += imageSize
                        
                        print("💾 QR-код сохранен в кэш. Размер кэша: \(self.qrCodeCache.count)/\(self.maxCacheSize) элементов, ~\(self.totalCacheSize / 1024) KB")
                        
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
        
        // Сохраняем назначение платежа для отображения
        DispatchQueue.main.async { [weak self] in
            self?.paymentPurpose = purpose
        }
        
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
            self.paymentPurpose = nil
        }
    }
    
    // MARK: - Cache Management
    func getCacheStatistics() -> (hits: Int, misses: Int, size: Int, count: Int) {
        return (cacheHits, cacheMisses, totalCacheSize, qrCodeCache.count)
    }
    
    func clearCache() {
        qrCodeCache.removeAll()
        cacheAccessOrder.removeAll()
        cacheHits = 0
        cacheMisses = 0
        totalCacheSize = 0
        print("🗑️ Кэш QR-кодов очищен")
    }
    
    func preloadCommonQRCodes() {
        // ОТКЛЮЧЕНО: Предзагрузка создавала проблемы производительности
        // Кэш будет заполняться автоматически при использовании
        print("ℹ️ Предзагрузка QR-кодов отключена для лучшей производительности")
        
        // Если нужна легкая предзагрузка, раскомментируйте код ниже
        /*
        // Предзагрузка только самых популярных комбинаций (уменьшено с 36 до 6)
        let commonRates = [12.0, 12.5]
        let commonAmounts = [1000.0, 2000.0, 5000.0]
        
        print("🚀 Начинаем легкую предзагрузку популярных QR-кодов...")
        
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            
            // Добавляем задержку, чтобы не блокировать UI при запуске
            Thread.sleep(forTimeInterval: 3.0)
            
            for rate in commonRates {
                for amount in commonAmounts {
                    let rubAmount = amount * rate
                    let qrText = self.buildQRCodeText(rmbAmount: amount, rubAmount: rubAmount)
                    
                    if !qrText.isEmpty && self.qrCodeCache.count < self.maxCacheSize {
                        let topText = "\(String(format: "%.0f", amount)) rmb / \(String(format: "%.0f", rubAmount)) руб."
                        let bottomText = "Курс: \(String(format: "%.2f", rate))"
                        
                        self.qrGenerator.generateQRCodeWithText(
                            qrText: qrText,
                            topText: topText,
                            bottomText: bottomText
                        ) { image in
                            if let image = image, self.qrCodeCache.count < self.maxCacheSize {
                                let cacheKey = "\(amount)_\(rubAmount)_\(self.currentQRFormat)"
                                self.qrCodeCache[cacheKey] = image
                                self.cacheAccessOrder.append(cacheKey)
                                
                                let imageSize = Int(image.size.width * image.size.height * 4)
                                self.totalCacheSize += imageSize
                            }
                        }
                        
                        // Пауза между генерациями для снижения нагрузки
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
            }
            
            DispatchQueue.main.async {
                print("✅ Предзагрузка завершена. Кэш содержит \(self.qrCodeCache.count) элементов")
            }
        }
        */
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

// MARK: - Edited Field Enum
enum EditedField {
    case none
    case exchangeRate
    case rmbAmount
    case rubAmount
}
