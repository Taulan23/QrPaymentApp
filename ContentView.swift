//
//  ContentView.swift
//  QRPayments
//
//  Created by QR Payments Team on 25/09/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = QRPaymentsViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Заголовок
                    VStack(spacing: 8) {
                        Text("QR Payments")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("Генератор QR-кодов СБП")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    
                    // Карточка с полями ввода
                    VStack(spacing: 16) {
                        // Курс валют
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Курс")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Введите курс", value: $viewModel.exchangeRate, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                        
                        // Количество RMB
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Количество RMB")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("Введите количество RMB", value: $viewModel.rmbAmount, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                        
                        // Отображение курса
                        if let rate = viewModel.exchangeRate {
                            HStack {
                                Text("Курс:")
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(rate, specifier: "%.2f")")
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Сумма в рублях
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Сумма в рублях")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            TextField("или введите сумму в рублях", value: $viewModel.rubAmount, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                        
                        // Переключатель номера договора
                        HStack {
                            Text("Номер договора")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.contractNumberEnabled)
                                .toggleStyle(SwitchToggleStyle(tint: .blue))
                        }
                        
                        // Поле номера договора
                        if viewModel.contractNumberEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Номер договора")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                TextField("Введите номер договора", text: $viewModel.contractNumber)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        
                        // Кнопка сохранения
                        Button(action: {
                            viewModel.saveQRCodeAlternative()
                        }) {
                            HStack {
                                if viewModel.isSaving {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                }
                                Text(viewModel.isSaving ? "Сохранение..." : "Сохранить в галерею")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.isSaving ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                        }
                        .disabled(viewModel.isSaving)
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Карточка с QR-кодом
                    VStack(spacing: 16) {
                        Text("QR-код для оплаты")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        // QR-код
                        if let qrImage = viewModel.qrCodeImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 250, height: 250)
                                .background(Color.white)
                                .cornerRadius(8)
                                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                                .onTapGesture {
                                    // Добавляем защиту от быстрых нажатий
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        viewModel.toggleQRFormat()
                                    }
                                }
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 250, height: 250)
                                .overlay(
                                    Text("Введите данные для расчета")
                                        .foregroundColor(.gray)
                                )
                        }
                        
                        // Текст под QR-кодом
                        if let displayText = viewModel.qrDisplayText {
                            Text(displayText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Переключатель формата
                        VStack(spacing: 8) {
                            Button(action: {
                                // Добавляем защиту от быстрых нажатий
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    viewModel.toggleQRFormat()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Переключить формат")
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                            }
                            
                            Text(viewModel.currentFormatDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            // Статистика кэша
                            let cacheStats = viewModel.getCacheStatistics()
                            VStack(spacing: 4) {
                                HStack {
                                    Image(systemName: "memorychip")
                                        .foregroundColor(.green)
                                    Text("Кэш: \(cacheStats.count) QR-кодов")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("~\(cacheStats.size / 1024) KB")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack {
                                    Image(systemName: "target")
                                        .foregroundColor(.blue)
                                    Text("Попаданий: \(cacheStats.hits)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.orange)
                                    Text("Промахов: \(cacheStats.misses)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                }
                .padding()
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            viewModel.loadSavedData()
        }
    }
}

#Preview {
    ContentView()
}
