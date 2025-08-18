protocol NetworkSettings {
    var queueAPI: String { get }
    var engineAPI: String { get }
    var renderer: String { get }
}

struct NetworkSettingsProduction: NetworkSettings {
    let queueAPI = "https://consumer.inapp.customer.io"
    let engineAPI = "https://engine.api.gist.build"
    let renderer = "https://renderer.gist.build/3.0"
}

struct NetworkSettingsDevelopment: NetworkSettings {
    let queueAPI = "https://consumer.dev.inapp.customer.io"
    let engineAPI = "https://engine.api.dev.gist.build"
    let renderer = "https://renderer.gist.build/3.0"
}

struct NetworkSettingsLocal: NetworkSettings {
    let queueAPI = "http://queue.api.local.gist.build:86"
    let engineAPI = "http://engine.api.local.gist.build:82"
    let renderer = "http://app.local.gist.build:8080/web"
}
