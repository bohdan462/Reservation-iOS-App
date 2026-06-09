//
//  HostLlamaBriefingRuntime.swift
//  Tryzub Reservations
//
//  llama.cpp adapter for host briefing generation via mattt/llama.swift (LlamaSwift).
//  Inference is isolated to this file — only prompts derived from HostLLMPacket are accepted.
//

import Foundation
import LlamaSwift

private let hostLlamaQwenImEndToken = String("<") + "|im_end|>"

// MARK: - Runtime diagnostics (developer diagnostics only)

struct HostLlamaRunDiagnostics: Equatable {
  var modelPath: String?
  var modelSource: String?
  var promptCharacterCount: Int = 0
  var promptTokenCount: Int = 0
  var contextWindow: UInt32 = 0
  var batchCapacity: Int32 = 0
  var contextBatchLimit: UInt32 = 0
  var maxOutputTokens: Int32 = 0
  var promptExceedsContext: Bool = false
  var promptExceedsBatchCapacity: Bool = false
  var initialDecodeCode: Int32?
  var generationDecodeCode: Int32?
  var lastError: String?
}

enum HostLlamaBriefingRuntimeDiagnostics {
  nonisolated(unsafe) static var lastRun = HostLlamaRunDiagnostics()
}

#if DEBUG
private func hostLlamaLogDebug(_ message: String) {
  print("[HostLlama] \(message)")
}
#endif

/// llama.cpp-backed runtime for presentation-only host briefing rewrites.
final actor HostLlamaBriefingRuntime: HostLocalModelRuntime {

  static let runtimeDisplayName = "llama.cpp"

  /// Swift adapter source is compiled into the app.
  static let isAdapterShellPresent = true

  /// True when llama.cpp / LlamaSwift SPM is linked and inference code compiles.
  static let isInferenceRuntimeLinked = true

  static let shared = HostLlamaBriefingRuntime()

  private static let maxOutputTokens: Int32 = 100
  private static let samplingTemperature = 0.1
  private static let contextWindow: UInt32 = 2048

  private static let promptEchoStopMarkers = [
    "Write the host briefing now:",
    "Approved facts:",
    "You are rewriting an approved restaurant host briefing",
    "Writing rules:",
    "Forbidden:"
  ]

  private var session: LlamaLoadedSession?
  private var sessionModelPath: String?

  var runtimeName: String { Self.runtimeDisplayName }

  var modelName: String? {
    HostLocalModelFileLocator.firstAvailableModelURL()?.lastPathComponent
  }

  private init() {}

  func generateBriefing(prompt: String) async throws -> String {
    guard let modelURL = HostLocalModelFileLocator.firstAvailableModelURL() else {
      throw HostLocalModelRuntimeError.modelMissing
    }

    let modelPath = modelURL.path
    if sessionModelPath != modelPath {
      session = nil
      sessionModelPath = modelPath
    }

    if session == nil {
      do {
        session = try LlamaLoadedSession(
          modelPath: modelPath,
          contextWindow: Self.contextWindow,
          temperature: Float(Self.samplingTemperature)
        )
      } catch let error as HostLocalModelRuntimeError {
        throw error
      } catch {
        throw HostLocalModelRuntimeError.modelLoadFailed(error.localizedDescription)
      }
    }

    guard let session else {
      throw HostLocalModelRuntimeError.modelLoadFailed("Llama session is unavailable.")
    }

    let inferencePrompt = Self.wrapPromptForQwenInstruct(prompt)
    var diagnostics = HostLlamaRunDiagnostics(
      modelPath: modelPath,
      modelSource: HostLocalModelFileLocator.modelSourceLabel(),
      promptCharacterCount: inferencePrompt.count,
      contextWindow: Self.contextWindow,
      maxOutputTokens: Self.maxOutputTokens
    )

    let generated: String
    do {
      generated = try session.generate(
        prompt: inferencePrompt,
        maxTokens: Self.maxOutputTokens,
        echoStopMarkers: Self.promptEchoStopMarkers,
        diagnostics: &diagnostics
      )
    } catch let error as HostLocalModelRuntimeError {
      diagnostics.lastError = error.errorDescription
      HostLlamaBriefingRuntimeDiagnostics.lastRun = diagnostics
      throw error
    } catch {
      let message = error.localizedDescription
      diagnostics.lastError = message
      HostLlamaBriefingRuntimeDiagnostics.lastRun = diagnostics
      throw HostLocalModelRuntimeError.generationFailed(message)
    }

    HostLlamaBriefingRuntimeDiagnostics.lastRun = diagnostics

    let sanitized = Self.sanitizeGeneratedBriefing(generated)
    let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw HostLocalModelRuntimeError.outputEmpty
    }
    return trimmed
  }

  private static func wrapPromptForQwenInstruct(_ prompt: String) -> String {
    """
    <|im_start|>system
    Rewrite the approved host facts into calm staff-facing prose. Obey every rule in the user message.
    
    <|im_start|>user
    \(prompt)
    
    <|im_start|>assistant
    """
  }

  private static func sanitizeGeneratedBriefing(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    for marker in promptEchoStopMarkers {
      if let range = text.range(of: marker) {
        text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }

    text = text
      .replacingOccurrences(of: "<|im_start|>", with: "")
      .replacingOccurrences(of: hostLlamaQwenImEndToken, with: "")
      .replacingOccurrences(of: "</s>", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    return text
  }

}

// MARK: - Llama session (C API wrapper)

private final class LlamaLoadedSession: @unchecked Sendable {
  /// Qwen2.5 GGUF metadata sets `tokenizer.ggml.add_bos_token = false`.
  private static let addBOSForPrompt = false

  private let model: OpaquePointer
  private let context: OpaquePointer
  private let vocab: OpaquePointer
  private let sampler: UnsafeMutablePointer<llama_sampler>?
  private let ownsBackend: Bool
  private let contextWindow: UInt32

  init(
    modelPath: String,
    contextWindow: UInt32,
    temperature: Float
  ) throws {
    llama_backend_init()
    ownsBackend = true

    var modelParams = llama_model_default_params()
    guard let loadedModel = llama_model_load_from_file(modelPath, modelParams) else {
      llama_backend_free()
      throw HostLocalModelRuntimeError.modelLoadFailed("Could not load GGUF at \(modelPath).")
    }
    model = loadedModel

    var contextParams = llama_context_default_params()
    contextParams.n_ctx = contextWindow
    contextParams.n_batch = contextWindow

    guard let loadedContext = llama_init_from_model(model, contextParams) else {
      llama_model_free(model)
      llama_backend_free()
      throw HostLocalModelRuntimeError.modelLoadFailed("Could not create llama context.")
    }
    context = loadedContext
    vocab = llama_model_get_vocab(model)
    self.contextWindow = contextWindow

    var samplerParams = llama_sampler_chain_default_params()
    let chain = llama_sampler_chain_init(samplerParams)
    llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
    llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
    llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: .min ... .max)))
    sampler = chain
  }

  deinit {
    if let sampler {
      llama_sampler_free(sampler)
    }
    llama_free(context)
    llama_model_free(model)
    if ownsBackend {
      llama_backend_free()
    }
  }

  func generate(
    prompt: String,
    maxTokens: Int32,
    echoStopMarkers: [String],
    diagnostics: inout HostLlamaRunDiagnostics
  ) throws -> String {
    let promptTokens = try tokenize(prompt, addBOS: Self.addBOSForPrompt)
    guard !promptTokens.isEmpty else {
      throw HostLocalModelRuntimeError.generationFailed("Prompt tokenization returned no tokens.")
    }

    let promptTokenCount = Int32(promptTokens.count)
    let contextBatchLimit = llama_n_batch(context)

    diagnostics.promptTokenCount = Int(promptTokenCount)
    diagnostics.batchCapacity = promptTokenCount
    diagnostics.contextBatchLimit = contextBatchLimit
    diagnostics.promptExceedsContext = Int(promptTokenCount) + Int(maxTokens) >= Int(contextWindow)
    diagnostics.promptExceedsBatchCapacity = UInt32(promptTokenCount) > contextBatchLimit

    guard Int(promptTokenCount) + Int(maxTokens) < Int(contextWindow) else {
      throw HostLocalModelRuntimeError.generationFailed(
        "Prompt is too long for local model context."
      )
    }

    guard UInt32(promptTokenCount) <= contextBatchLimit else {
      throw HostLocalModelRuntimeError.generationFailed(
        "Prompt exceeds local model batch capacity (\(promptTokenCount) > \(contextBatchLimit))."
      )
    }

    if let memory = llama_get_memory(context) {
      llama_memory_clear(memory, true)
    }

    #if DEBUG
    hostLlamaLogDebug(
      "generate path=\(diagnostics.modelPath ?? "unknown") promptChars=\(diagnostics.promptCharacterCount) promptTokens=\(promptTokenCount) ctx=\(contextWindow) batchLimit=\(contextBatchLimit)"
    )
    let preview = String(prompt.prefix(300))
    hostLlamaLogDebug("promptPreview=\(preview)")
    #endif

    var mutablePromptTokens = promptTokens
    var batch = mutablePromptTokens.withUnsafeMutableBufferPointer { buffer in
      llama_batch_get_one(buffer.baseAddress!, promptTokenCount)
    }
    setLogitsOnLastToken(&batch)

    let initialCode = llama_decode(context, batch)
    diagnostics.initialDecodeCode = initialCode

    #if DEBUG
    hostLlamaLogDebug("initialDecodeCode=\(initialCode)")
    #endif

    guard initialCode == 0 else {
      throw HostLocalModelRuntimeError.generationFailed(
        "Initial llama_decode failed with code \(initialCode)."
      )
    }

    var generated = ""
    let eosToken = llama_vocab_eos(vocab)

    for _ in 0..<maxTokens {
      let nextToken: llama_token
      if let sampler {
        nextToken = llama_sampler_sample(sampler, context, batch.n_tokens - 1)
        llama_sampler_accept(sampler, nextToken)
      } else {
        guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
          throw HostLocalModelRuntimeError.generationFailed("Failed to read logits.")
        }
        let vocabSize = Int(llama_vocab_n_tokens(vocab))
        var bestLogit = logits[0]
        var bestToken: llama_token = 0
        for tokenIndex in 1..<vocabSize {
          if logits[tokenIndex] > bestLogit {
            bestLogit = logits[tokenIndex]
            bestToken = llama_token(tokenIndex)
          }
        }
        nextToken = bestToken
      }

      if shouldStopGeneration(token: nextToken, eosToken: eosToken, generated: generated) {
        break
      }

      generated += try tokenPiece(for: nextToken)

      if echoStopMarkers.contains(where: { generated.contains($0) }) {
        for marker in echoStopMarkers where generated.contains(marker) {
          if let range = generated.range(of: marker) {
            generated = String(generated[..<range.lowerBound])
          }
        }
        break
      }

      var next = nextToken
      batch = withUnsafeMutablePointer(to: &next) { pointer in
        llama_batch_get_one(pointer, 1)
      }
      if let logits = batch.logits {
        logits[0] = 1
      }

      let decodeCode = llama_decode(context, batch)
      if decodeCode != 0 {
        diagnostics.generationDecodeCode = decodeCode
        throw HostLocalModelRuntimeError.generationFailed(
          "Token llama_decode failed with code \(decodeCode)."
        )
      }
    }

    return generated
  }

  private func shouldStopGeneration(
    token: llama_token,
    eosToken: llama_token,
    generated: String
  ) -> Bool {
    if token == eosToken {
      return true
    }

    let piece = (try? tokenPiece(for: token)) ?? ""
    if piece.contains(hostLlamaQwenImEndToken) {
      return true
    }
    if piece.contains("</s>") {
      return true
    }
    if generated.contains(hostLlamaQwenImEndToken) {
      return true
    }
    return false
  }

  private func setLogitsOnLastToken(_ batch: inout llama_batch) {
    guard batch.n_tokens > 0, let logits = batch.logits else { return }
    for index in 0..<Int(batch.n_tokens) {
      logits[index] = 0
    }
    logits[Int(batch.n_tokens) - 1] = 1
  }

  private func tokenize(_ text: String, addBOS: Bool) throws -> [llama_token] {
    let utf8Count = text.utf8.count
    var maxTokenCount = max(utf8Count + 16, 256)
    var tokens = [llama_token](repeating: 0, count: maxTokenCount)

  var tokenCount = text.withCString { cString in
      llama_tokenize(
        vocab,
        cString,
        Int32(utf8Count),
        &tokens,
        Int32(maxTokenCount),
        addBOS,
        true
      )
    }

    if tokenCount < 0 {
      maxTokenCount = max(Int(-tokenCount), maxTokenCount) + 16
      tokens = [llama_token](repeating: 0, count: maxTokenCount)
      tokenCount = text.withCString { cString in
        llama_tokenize(
          vocab,
          cString,
          Int32(utf8Count),
          &tokens,
          Int32(maxTokenCount),
          addBOS,
          true
        )
      }
    }

    guard tokenCount > 0 else {
      throw HostLocalModelRuntimeError.generationFailed("Failed to tokenize prompt.")
    }

    return Array(tokens.prefix(Int(tokenCount)))
  }

  private func tokenPiece(for token: llama_token) throws -> String {
    var buffer = [CChar](repeating: 0, count: 64)
    let length = llama_token_to_piece(
      vocab,
      token,
      &buffer,
      Int32(buffer.count),
      0,
      false
    )

    guard length > 0 else {
      return ""
    }

    return String(cString: buffer)
  }
}
