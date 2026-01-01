# OpenAIClient Library

A lightweight, reusable Swift library that wraps the MacPaw/OpenAI SDK with a focus on tool/function calling support.

## Purpose

This library provides:
- A thin, actor-based wrapper around the OpenAI SDK
- Type-safe tool/function definition system
- Example tool implementations
- Reusable across projects

**Note**: This is a library module. Application-specific logic (like configuration management and service layers) should live in your app, not here.

## Features

- ✅ Actor-based client for thread safety
- ✅ Type-safe Tool Definition Protocol
- ✅ Built-in example tools
- ✅ Async/await support
- ✅ Simple, focused API

## Components

### OpenAIClient (Actor)

Thread-safe wrapper around the OpenAI SDK.

```swift
import OpenAIClient

let client = OpenAIClient(apiKey: "your-api-key")

// Simple message
let response = try await client.sendMessage("Hello, AI!")
print(response)
```

### Tool System

The `ToolDefinition` protocol provides a type-safe way to define tools:

```swift
protocol ToolDefinition {
    static var name: String { get }
    static var description: String { get }
    static var parametersSchema: JSONSchema { get }
    func execute(arguments: [String: Any]) async throws -> String
}
```

### Creating Custom Tools

```swift
struct WeatherTool: ToolDefinition {
    static let name = "get_weather"
    static let description = "Get weather for a location"
    static let parametersSchema: JSONSchema = .init(
        .type(.object),
        .properties([
            "location": .init(
                .type(.string),
                .description("City name")
            )
        ]),
        .required(["location"])
    )
    
    func execute(arguments: [String: Any]) async throws -> String {
        guard let location = arguments["location"] as? String else {
            throw ToolError.missingArgument("location")
        }
        // Your implementation here
        return "Weather in \(location): 72°F, Sunny"
    }
}

// Convert to OpenAI format
let tool = ToolConverter.convert(WeatherTool.self)
```

## Built-in Example Tools

### GetCurrentTimeTool
```swift
let tool = GetCurrentTimeTool()
let time = try await tool.execute(arguments: ["timezone": "America/New_York"])
```

### CalculatorTool
```swift
let tool = CalculatorTool()
let result = try await tool.execute(arguments: ["expression": "2 + 2 * 5"])
```

## Design Philosophy

This library is intentionally minimal and focused:
- **No configuration management** - That's app-specific
- **No service layers** - Apps should implement their own
- **No UI components** - Pure business logic only
- **No persistence** - Apps handle their own storage

This keeps the library reusable across different projects with different needs.
