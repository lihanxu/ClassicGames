// swift-tools-version: 5.9
import PackageDescription

// Narrow logic harness; it does not build the UI or change the iOS product.
let package = Package(
    name: "SokobanLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SokobanLogic", path: "ClassicGames", exclude: [
            "App", "Breakout", "Game2048", "Gomoku", "Memory", "Minesweeper",
            "Platformer", "Resources", "Snake", "Shell/AppRouter.swift", "Shell/GameCatalog.swift",
            "Shell/GameFrame.swift", "Shell/HomeView.swift", "Shell/ScoreStore.swift",
            "Sokoban/SokobanAudio.swift", "Sokoban/SokobanScreen.swift", "Sokoban/SokobanV4Chrome.swift"
        ], sources: [
            "Shell/GameID.swift", "Sokoban/SokobanLevel.swift", "Sokoban/SokobanLevels.swift",
            "Sokoban/SokobanModel.swift", "Sokoban/SokobanPersistence.swift", "Sokoban/SokobanPresentation.swift",
            "Sokoban/SokobanReferenceSolutions.swift", "Sokoban/SokobanScoring.swift",
            "Sokoban/SokobanReplay.swift", "Sokoban/SokobanHintSearch.swift", "Sokoban/SokobanDPadRepeat.swift"
        ]),
        .testTarget(name: "SokobanLogicTests", dependencies: ["SokobanLogic"], path: "Tests/SokobanLogicTests")
    ]
)
