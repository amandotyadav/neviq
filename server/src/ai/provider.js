import { GoogleGenAI } from '@google/genai';
import { env } from '../config/env.js';
import { AppError, aiUnavailable } from '../utils/errors.js';
import { logger } from '../utils/logger.js';

/**
 * AI provider abstraction over the official Google Gen AI SDK (Gemini).
 *
 * Interface (provider-neutral, so callers never touch SDK shapes):
 *   model: string
 *   respond({ instructions, input, tools, maxOutputTokens }) ->
 *     { text, toolCalls: [{ callId, name, arguments(JSON string) }], rawContent }
 *   structured({ instructions, input, name, schema, maxOutputTokens }) -> object
 *
 * `input` items:
 *   { role: 'user' | 'assistant', content: string }
 *   { type: 'model_content', content }                       (rawContent from a previous respond())
 *   { type: 'tool_result', callId, name, output: string }    (JSON string)
 * `tools`: [{ name, description, parameters (JSON schema) }]
 *
 * Tests inject a fake with setAIProvider(); `null` simulates "no key".
 */

let override;
let cached;

export function setAIProvider(provider) {
  override = provider;
}

export function getAIProvider() {
  if (override !== undefined) return override;
  if (!env.GEMINI_API_KEY) return null;
  cached ??= createGeminiProvider({ apiKey: env.GEMINI_API_KEY, model: env.GEMINI_MODEL, timeoutMs: env.AI_TIMEOUT_MS });
  return cached;
}

export function requireAI() {
  const provider = getAIProvider();
  if (!provider) {
    throw aiUnavailable('Saathi AI is not configured on this server (no AI API key). Discovery, eligibility checks, saving, and tracking still work.');
  }
  return provider;
}

function mapError(err) {
  if (err instanceof AppError) return err;
  const status = err?.status ?? err?.code;
  logger.warn('AI provider error', { status, name: err?.name, message: err?.message });
  if (err?.name === 'AbortError' || /timed? ?out|deadline/i.test(err?.message ?? '')) {
    return new AppError(504, 'AI_TIMEOUT', 'Saathi took too long to respond. Please try again.');
  }
  if (status === 401 || status === 403 || /API key/i.test(err?.message ?? '')) {
    return aiUnavailable('Saathi AI is misconfigured on the server (API key rejected).');
  }
  if (status === 429) return new AppError(503, 'AI_BUSY', 'Saathi is busy right now. Please try again in a minute.');
  return aiUnavailable('Saathi could not complete this request. Please try again.');
}

/** Converts neutral input items into Gemini `contents`. */
export function toGeminiContents(input) {
  const contents = [];
  for (const item of input) {
    if (item.type === 'model_content') {
      contents.push(item.content);
    } else if (item.type === 'tool_result') {
      let response;
      try { response = { output: JSON.parse(item.output) }; } catch { response = { output: item.output }; }
      const part = { functionResponse: { name: item.name, response, ...(item.callId ? { id: item.callId } : {}) } };
      const last = contents.at(-1);
      // Consecutive results are sent together in one user turn.
      if (last?.role === 'user' && last.parts.every((p) => p.functionResponse)) last.parts.push(part);
      else contents.push({ role: 'user', parts: [part] });
    } else {
      contents.push({ role: item.role === 'assistant' ? 'model' : 'user', parts: [{ text: item.content }] });
    }
  }
  return contents;
}

export function createGeminiProvider({ apiKey, model, timeoutMs }) {
  const client = new GoogleGenAI({ apiKey });
  const httpOptions = { timeout: timeoutMs };

  return {
    model,
    async respond({ instructions, input, tools, maxOutputTokens = 1200 }) {
      try {
        const response = await client.models.generateContent({
          model,
          contents: toGeminiContents(input),
          config: {
            systemInstruction: instructions,
            maxOutputTokens,
            httpOptions,
            ...(tools?.length
              ? { tools: [{ functionDeclarations: tools.map((t) => ({ name: t.name, description: t.description, parametersJsonSchema: t.parameters })) }] }
              : {}),
          },
        });
        const toolCalls = (response.functionCalls ?? []).map((c) => ({
          callId: c.id ?? c.name,
          name: c.name,
          arguments: JSON.stringify(c.args ?? {}),
        }));
        return { text: toolCalls.length ? '' : (response.text ?? ''), toolCalls, rawContent: response.candidates?.[0]?.content };
      } catch (err) {
        throw mapError(err);
      }
    },
    async structured({ instructions, input, name, schema, maxOutputTokens = 2500 }) {
      let response;
      try {
        response = await client.models.generateContent({
          model,
          contents: typeof input === 'string' ? input : toGeminiContents(input),
          config: {
            systemInstruction: instructions,
            maxOutputTokens,
            httpOptions,
            responseMimeType: 'application/json',
            responseJsonSchema: schema,
          },
        });
      } catch (err) {
        throw mapError(err);
      }
      try {
        return JSON.parse(response.text);
      } catch {
        logger.warn('AI returned non-JSON structured output', { name });
        throw new AppError(502, 'AI_INVALID_OUTPUT', 'Saathi returned an incomplete answer. Please try again.');
      }
    },
  };
}
