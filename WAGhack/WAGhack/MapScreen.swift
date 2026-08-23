//
//  MapScreen.swift
//  WAGhack
//

import SwiftUI
import SwiftData
import MapKit

// 画面1: 現在地をマップで表示し、右上の「追加」ボタンで住所をリストに保存する画面
struct MapScreen: View {
    @Environment(\.modelContext) private var modelContext
    // リスト画面とタブ選択・フォーカス位置を共有するためのオブジェクト
    @Environment(AppNavigator.self) private var navigator
    @State private var locationManager = LocationManager()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isSaving = false
    @State private var errorMessage: String?
    // nilでなければ画面下部にスナックバーとして表示される
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            Map(position: $cameraPosition) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
            }
            // 標準の大きい見出しではなく、アプリの用途が伝わるラベルを自前で表示する
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("現在地を保存")
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addCurrentLocation()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Label("追加", systemImage: "plus")
                        }
                    }
                    .disabled(isSaving || locationManager.currentLocation == nil)
                }
            }
            .alert("エラー", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            // リスト画面で住所がタップされたら、その地点にカメラを移動する
            .onChange(of: navigator.focusTarget) { _, target in
                guard let target else { return }
                withAnimation {
                    cameraPosition = .region(
                        MKCoordinateRegion(
                            center: target.coordinate,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    )
                }
                // 移動が終わったら消費済みとしてクリアしておく（再タップ時にonChangeが発火するように）
                navigator.focusTarget = nil
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdating()
        }
        .toast(message: $toastMessage)
    }

    // 現在地を逆ジオコーディングして住所として保存する
    private func addCurrentLocation() {
        guard let coordinate = locationManager.currentLocation else { return }
        isSaving = true
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        Task {
            let address = await reverseGeocode(location: location)
            let saved = SavedLocation(
                address: address,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timestamp: Date()
            )
            modelContext.insert(saved)
            isSaving = false
            // 保存が完了したことをスナックバーで知らせる
            toastMessage = "現在地を保存しました"
        }
    }

    // MapKitのMKReverseGeocodingRequestで座標から住所文字列に変換する（CLGeocoderはiOS26で非推奨のため使わない）
    private func reverseGeocode(location: CLLocation) async -> String {
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return "住所不明 (\(location.coordinate.latitude), \(location.coordinate.longitude))"
        }
        do {
            let mapItems = try await request.mapItems
            if let address = mapItems.first?.address {
                return address.fullAddress
            }
        } catch {
            errorMessage = "住所の取得に失敗しました: \(error.localizedDescription)"
        }
        return "住所不明 (\(location.coordinate.latitude), \(location.coordinate.longitude))"
    }
}

#Preview {
    MapScreen()
        .modelContainer(for: SavedLocation.self, inMemory: true)
        .environment(AppNavigator())
}
