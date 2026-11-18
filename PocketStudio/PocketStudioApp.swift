import SwiftUI

@main
struct PocketStudioApp: App {
    @StateObject private var models = ModelManager()
    @StateObject private var gallery = Gallery()
    @StateObject private var generator = Generator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(models)
                .environmentObject(gallery)
                .environmentObject(generator)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var models: ModelManager
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            CreateView(goToModels: { tab = 2 })
                .tabItem { Label("Create", systemImage: "wand.and.stars") }
                .tag(0)
            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle.angled") }
                .tag(1)
            ModelsView()
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(2)
        }
        .tint(.purple)
        .onAppear {
            if models.installed.isEmpty { tab = 2 }
        }
    }
}
