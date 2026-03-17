# Skill Router

Central module for mapping paper content to domain-specific AI research skills.

---

## Interface

### Input Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `paper_metadata` | object | Contains `title`, `abstract`, `keywords`, `venue` fields extracted from the paper |
| `topic_description` | string | Free-text description of the research topic (used when paper_metadata is unavailable or for discovery phases) |
| `phase_type` | enum | One of: `discover`, `discuss`, `read`, `write`, `trending` |
| `user_domain_override` | string (optional) | Comma-separated category names to ADD to auto-detected categories |
| `user_domain_only` | string (optional) | Comma-separated category names to USE EXCLUSIVELY, replacing auto-detection entirely |

### Output Format

The router outputs a JSON object with two arrays:

```json
{
  "primary": [
    {
      "category": "<category-name>",
      "skill": "<skill-name>",
      "prompt": "<phase-appropriate prompt to inject into the skill>"
    }
  ],
  "secondary": [
    {
      "category": "<category-name>",
      "skill": "<skill-name>",
      "prompt": "<phase-appropriate prompt to inject into the skill>"
    }
  ]
}
```

- `primary`: Categories and skills that are central to the paper's main contribution.
- `secondary`: Categories and skills relevant to the paper's methodology or experimental context but not the core topic.
- Each array entry contains a `category` name, a resolved `skill` name, and a `prompt` string tailored to the current phase.

---

## Detection Logic

The router follows a three-branch decision tree:

### Branch 1: `user_domain_only` is set
If the `user_domain_only` parameter is provided, skip all auto-detection. Use only the categories explicitly specified by the user. All specified categories are treated as `primary`. No keyword scanning is performed.

### Branch 2: `user_domain_override` is set
If the `user_domain_override` parameter is provided (but `user_domain_only` is not), run auto-detection from `paper_metadata` or `topic_description` as normal, then merge the user-specified categories into the result. User-specified categories are appended to the auto-detected `primary` list if not already present.

### Branch 3: Default auto-detection
If neither override parameter is set, run keyword scanning against `paper_metadata` (title, abstract, keywords, venue) or `topic_description` to determine matching categories.

### Primary vs. Secondary Heuristic

After keyword matching, classify each matched category as primary or secondary using the following rule:

- **Primary**: Keywords that trigger the match appear in the paper's **title** or in the **first 2 sentences of the abstract**. These topics are likely the paper's central contribution.
- **Secondary**: Keywords that trigger the match appear only in the **methodology section**, **experiments section**, or later portions of the abstract. These topics are likely supporting techniques or evaluation context rather than the main contribution.

When only a `topic_description` is available (no structured abstract), all matched categories default to primary.

---

## Full Category Mapping Table

| # | Category | Trigger Keywords | Available Skills |
|---|----------|-----------------|-----------------|
| 1 | Model-Architecture | transformer, attention mechanism, SSM, state-space, Mamba, RWKV, linear attention, architecture design, backbone | litgpt, mamba, nanogpt, rwkv, torchtitan |
| 2 | Tokenization | tokenizer, BPE, WordPiece, subword, vocabulary design | huggingface-tokenizers, sentencepiece |
| 3 | Fine-Tuning | fine-tuning, LoRA, QLoRA, adapter, PEFT, instruction tuning, SFT | axolotl, llama-factory, peft, unsloth |
| 4 | Mechanistic-Interpretability | interpretability, mechanistic, probing, circuit analysis, sparse autoencoder, superposition, causal intervention | transformer-lens, saelens, pyvene, nnsight |
| 5 | Data-Processing | data curation, deduplication, data quality, pretraining data, data filtering | ray-data, nemo-curator |
| 6 | Post-Training | RLHF, DPO, PPO, GRPO, preference optimization, reward model, alignment training, policy optimization | trl-fine-tuning, grpo-rl-training, openrlhf, simpo, verl |
| 7 | Safety-Alignment | safety, guardrails, jailbreak, red teaming, content moderation, constitutional AI, prompt injection | constitutional-ai, llamaguard, nemo-guardrails, prompt-guard |
| 8 | Distributed-Training | distributed training, model parallelism, tensor parallelism, FSDP, ZeRO, multi-GPU, pipeline parallelism | megatron-core, deepspeed, pytorch-fsdp2, accelerate |
| 9 | Infrastructure | GPU cloud, serverless compute, spot instances, multi-cloud | modal, skypilot, lambda-labs |
| 10 | Optimization | quantization, 4-bit, 8-bit, flash attention, INT4, FP8, model compression, pruning, memory efficiency | flash-attention, bitsandbytes, gptq, awq, hqq, gguf |
| 11 | Evaluation | benchmark, MMLU, HumanEval, GSM8K, leaderboard, evaluation methodology, metrics design | lm-evaluation-harness, bigcode-evaluation-harness, nemo-evaluator |
| 12 | Inference-Serving | inference serving, throughput, PagedAttention, KV cache, batching, deployment optimization | vllm, tensorrt-llm, llama.cpp, sglang |
| 13 | MLOps | experiment tracking, model registry, hyperparameter sweep | weights-and-biases, mlflow, tensorboard |
| 14 | Agents | AI agent, tool use, function calling, ReAct, autonomous agent, multi-agent, agentic workflow | langchain, llamaindex, crewai, autogpt |
| 15 | RAG | retrieval-augmented generation, RAG, vector database, dense retrieval, semantic search | chroma, faiss, sentence-transformers, pinecone, qdrant |
| 16 | Prompt-Engineering | prompt optimization, structured output, constrained generation, prompt programming | dspy, instructor, guidance, outlines |
| 17 | Observability | LLM observability, tracing, LLM monitoring, evaluation pipeline | langsmith, phoenix |
| 18 | Multimodal | multimodal, vision-language, VLM, text-to-image, diffusion, image generation, video understanding, speech recognition, audio generation, CLIP, contrastive learning, segmentation, image editing, style transfer, text-to-video, text-to-motion | clip, whisper, llava, stable-diffusion, segment-anything, blip-2, audiocraft |
| 19 | Emerging-Techniques | mixture of experts, MoE, model merging, long context, context extension, speculative decoding (algorithm-side), knowledge distillation, sparsity | moe-training, model-merging, long-context, speculative-decoding, knowledge-distillation, model-pruning |
| 20 | ML-Paper-Writing | *Not keyword-triggered — auto-invoked by Write phase* | ml-paper-writing |
| 21 | Research-Ideation | *Not keyword-triggered — auto-invoked by Discover (search strategy) and Discuss (ideation)* | brainstorming-research-ideas, creative-thinking-for-research |

---

## Intra-Category Skill Selection

### General Rule
Default to the **first skill listed** in the category's Available Skills column if no finer-grained keyword matches a specific skill within the category. If multiple finer-grained keywords match different skills within the same category, select all matching skills up to a **maximum of 3 per category**.

### Selection Examples

| Trigger Condition | Selected Skill(s) |
|-------------------|-------------------|
| Fine-Tuning triggered + "LoRA" in text | `peft` |
| Fine-Tuning triggered + "full fine-tuning at scale" in text | `unsloth` or `axolotl` |
| Multimodal triggered + "text-to-image" in text | `stable-diffusion` |
| Multimodal triggered + "VLM" in text | `clip` + `llava` |
| Optimization triggered + no specific keyword match | `flash-attention` (first in list) |

---

## Phase-Specific Behavior

| Phase | What gets invoked | Detail level |
|-------|-------------------|-------------|
| **Discover** | Primary only (top 1-2 categories) + `research-ideation` for search strategy | Lightweight — inform search keywords and quick-read assessment |
| **Discuss** | All primary + `research-ideation` (always) | Full depth — expert perspectives injected into every discussion turn |
| **Read** | All primary | Moderate — methodology-level analysis, no cross-paper ideation |
| **Write** | All primary + `ml-paper-writing` (always) | Full depth — technical accuracy check for written content |
| **Trending** | Top 1 primary only | Minimal — one-sentence domain positioning per paper |

---

## User Override

### Syntax

```
/research read 2401.12345 --domain fine-tuning,multimodal
/research discover "pose estimation" --domain-only multimodal
```

### Rules

1. Multiple categories are specified via comma separation with no spaces around commas.
2. Category names must match the mapping table. Semantic matching is acceptable — for example, `"finetuning"` matches `"Fine-Tuning"`, `"rag"` matches `"RAG"`.
3. `--domain` is **additive**: the specified categories are merged with auto-detected categories. Auto-detection still runs and its results are preserved.
4. `--domain-only` is **exclusive**: the specified categories entirely replace auto-detected categories. Auto-detection is skipped.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| No category matched (paper outside AI/ML) | Proceed without domain skill injection; log warning. Phase executes with generic analysis only. |
| Matched skill file not found or fails to load | Skip that skill, proceed with remaining matched skills; log warning. |
| Invalid `--domain` value | Report available category names and ask user to retry. |
| All matched skills fail to load | Proceed without domain injection (same as no-match case). |

---

## Performance Considerations

- **Discover / Trending**: The skill router runs once per phase invocation, not once per paper. For batch trending analysis over many papers, a single routing decision is made at the start.
- **Read**: The skill router runs once per paper. This is acceptable because read is a deep, single-paper operation.
- **Discuss**: Skills are loaded at discussion setup and reused across the entire discussion loop. The router is not re-invoked on each conversational turn.
- **Write**: Skills are loaded once per section write, not once per sentence or paragraph.
- **Session-level caching**: Within a session, category detection results are cached. If the same topic or the same set of papers is processed again, prior routing decisions are reused without re-running keyword detection.
