//
//  HostLlamaBriefingRuntime.swift
//  Tryzub Reservations
//
//  llama.cpp adapter for host briefing generation via mattt/llama.swift (LlamaSwift).
//  Inference is isolated to this file — only prompts derived from HostLLMPacket are accepted.
//

import Foundation
import LlamaSwift

/// llama.cpp-backed runtime for presentation-only host briefing rewrites.
final actor HostLlamaBriefingRuntime: HostLocalModelRuntime {

  static let runtimeDisplayName = "llama.cpp"

  /// Swift adapter source is compiled into the app.
  static let isAdapterShellPresent = true

  /// True when llama.cpp / LlamaSwift SPM is linked and inference code compiles.
  static let isInferenceRuntimeLinked = true

  static let shared = HostLlamaBriefingRuntime()

  private static let maxOutputTokens = 120
  private static let samplingTemperature = 0.2
  private static let contextWindow = UInt32(2048)

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

    let generated: String
    do {
      generated = try session.generate(
        prompt: prompt,
        maxTokens: Int32(Self.maxOutputTokens)
      )
    } catch let error as HostLocalModelRuntimeError {
      throw error
    } catch {
      throw HostLocalModelRuntimeError.generationFailed(error.localizedDescription)
    }

    let trimmed = generated.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      throw HostLocalModelRuntimeError.outputEmpty
    }
    return trimmed
  }
}

// MARK: - Llama session (C API wrapper)

private final class LlamaLoadedSession: @unchecked Sendable {
  private let model: OpaquePointer
  private let context: OpaquePointer
  private let vocab: OpaquePointer
  private let sampler: UnsafeMutablePointer<llama_sampler>?
  private let ownsBackend: Bool

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
    contextParams.n_batch = 512

    guard let loadedContext = llama_init_from_model(model, contextParams) else {
      llama_model_free(model)
      llama_backend_free()
      throw HostLocalModelRuntimeError.modelLoadFailed("Could not create llama context.")
    }
    context = loadedContext
    vocab = llama_model_get_vocab(model)

    var samplerParams = llama_sampler_chain_default_params()
    let chain = llama_sampler_chain_init(samplerParams)
    llama_sampler_chain_add(chain, llama_sampler_init_temp(temperature))
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

  func generate(prompt: String, maxTokens: Int32) throws -> String {
    let promptTokens = try tokenize(prompt, addBOS: true)
    guard !promptTokens.isEmpty else {
      throw HostLocalModelRuntimeError.generationFailed("Prompt tokenization returned no tokens.")
    }

    var batch = llama_batch_init(512, 0, 1)
    defer { llama_batch_free(batch) }

    batch.n_tokens = Int32(promptTokens.count)
    for index in 0..<promptTokens.count {
      batch.token[index] = promptTokens[index]
      batch.pos[index] = Int32(index)
      batch.n_seq_id[index] = 1
      if let seqIDs = batch.seq_id, let seqID = seqIDs[index] {
        seqID[0] = 0
      }
      batch.logits[index] = 0
    }
    if batch.n_tokens > 0 {
      batch.logits[Int(batch.n_tokens) - 1] = 1
    }

    guard llama_decode(context, batch) == 0 else {
      throw HostLocalModelRuntimeError.generationFailed("Initial llama_decode failed.")
    }

    var generated = ""
    var currentPosition = batch.n_tokens
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

      if nextToken == eosToken {
        break
      }

      generated += try tokenPiece(for: nextToken)

      batch.n_tokens = 1
      batch.token[0] = nextToken
      batch.pos[0] = currentPosition
      batch.n_seq_id[0] = 1
      if let seqIDs = batch.seq_id, let seqID = seqIDs[0] {
        seqID[0] = 0
      }
      batch.logits[0] = 1
      currentPosition += 1

      guard llama_decode(context, batch) == 0 else {
        throw HostLocalModelRuntimeError.generationFailed("Token llama_decode failed.")
      }
    }

    return generated
  }

  private func tokenize(_ text: String, addBOS: Bool) throws -> [llama_token] {
    let utf8Count = text.utf8.count
    let maxTokenCount = utf8Count + 8
    var tokens = [llama_token](repeating: 0, count: maxTokenCount)

    let tokenCount = text.withCString { cString in
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
