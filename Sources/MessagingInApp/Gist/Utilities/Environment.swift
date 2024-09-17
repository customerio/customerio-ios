public enum GistEnvironment {
    case local
    case development
    case production
}

extension GistEnvironment {
    var networkSettings: NetworkSettings {
        switch self {
        case .development:
            return NetworkSettingsDevelopment()
        case .local:
            return NetworkSettingsLocal()
        case .production:
            return NetworkSettingsProduction()
        }
    }
}
