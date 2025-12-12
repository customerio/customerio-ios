protocol NetworkSettings {
    var queueAPI: String { get }
    var engineAPI: String { get }
    var renderer: String { get }
    var sseAPI: String { get }
}

struct NetworkSettingsProduction: NetworkSettings {
    let queueAPI = "https://consumer.inapp.customer.io"
    let engineAPI = "https://engine.api.gist.build"
    let renderer = "https://renderer.gist.build/3.0"
    let sseAPI = "https://realtime.inapp.customer.io/api/v3/sse"
}

struct NetworkSettingsDevelopment: NetworkSettings {
    let queueAPI = "https://consumer.dev.inapp.customer.io"
    let engineAPI = "https://engine.api.dev.gist.build"
    let renderer = "https://renderer.gist.build/3.0"
    let sseAPI = "https://realtime.inapp.customer.io/api/v3/sse"
}

struct NetworkSettingsLocal: NetworkSettings {
    let queueAPI = "http://queue.api.local.gist.build:86"
    let engineAPI = "http://engine.api.local.gist.build:82"
    let renderer = "http://app.local.gist.build:8080/web"
    let sseAPI = "http://realtime.api.local.gist.build:86/api/v3/sse"
}
