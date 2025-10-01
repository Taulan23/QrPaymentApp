//
//  QRCodeGenerator.swift
//  QRPayments
//
//  Created by QR Payments Team on 25/09/2025.
//

import UIKit
import CoreImage

class QRCodeGenerator {
    
    // Переиспользуемый контекст для оптимизации
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    
    func generateQRCode(from string: String, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            let data = string.data(using: .utf8)
            
            guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            filter.setValue(data, forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel") // Средний уровень коррекции (было H)
            
            guard let outputImage = filter.outputImage else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            // Увеличиваем размер QR-кода для лучшего качества
            let scale = 10.0
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let scaledImage = outputImage.transformed(by: transform)
            
            // Конвертируем в UIImage с переиспользуемым контекстом
            guard let cgImage = self.ciContext.createCGImage(scaledImage, from: scaledImage.extent) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let qrImage = UIImage(cgImage: cgImage)
            
            DispatchQueue.main.async {
                completion(qrImage)
            }
        }
    }
    
    func generateQRCodeWithText(qrText: String, topText: String, bottomText: String, completion: @escaping (UIImage?) -> Void) {
        generateQRCode(from: qrText) { [weak self] qrImage in
            guard let qrImage = qrImage else {
                completion(nil)
                return
            }
            
            self?.createImageWithText(qrImage: qrImage, topText: topText, bottomText: bottomText, completion: completion)
        }
    }
    
    private func createImageWithText(qrImage: UIImage, topText: String, bottomText: String, completion: @escaping (UIImage?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            // Проверяем валидность входных данных
            guard qrImage.size.width > 0 && qrImage.size.height > 0 else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            
            let qrSize = CGSize(width: 300, height: 300)
            let textHeight: CGFloat = 60
            let totalHeight = qrSize.height + (textHeight * 2)
            let totalWidth = qrSize.width
            
            // Используем более безопасный способ создания контекста
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: totalWidth, height: totalHeight))
            let finalImage = renderer.image { context in
                // Белый фон
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
                
                // Рисуем QR-код в центре
                let qrRect = CGRect(x: 0, y: textHeight, width: qrSize.width, height: qrSize.height)
                qrImage.draw(in: qrRect)
                
                // Настройки для текста
                let textAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: {
                        let style = NSMutableParagraphStyle()
                        style.alignment = .center
                        return style
                    }()
                ]
                
                // Рисуем верхний текст
                let topTextRect = CGRect(x: 0, y: 10, width: totalWidth, height: textHeight - 20)
                topText.draw(in: topTextRect, withAttributes: textAttributes)
                
                // Рисуем нижний текст
                let bottomTextRect = CGRect(x: 0, y: textHeight + qrSize.height + 10, width: totalWidth, height: textHeight - 20)
                bottomText.draw(in: bottomTextRect, withAttributes: textAttributes)
            }
            
            DispatchQueue.main.async {
                completion(finalImage)
            }
        }
    }
}
