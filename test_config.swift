import OpenAI

let config = OpenAI.Configuration(
    token: "test",
    host: "localhost:11434",
    scheme: "http"
)
print("Host: \(config)")
