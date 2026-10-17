import 'package:intl/intl.dart';

/// Represents model token usage metrics from the Antigravity CLI.
class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final int cacheReadTokens;
  final int thinkingTokens;
  final int? contextWindowLimit;

  const TokenUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
    this.cacheReadTokens = 0,
    this.thinkingTokens = 0,
    this.contextWindowLimit,
  });

  factory TokenUsage.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const TokenUsage();

    final input = _parseInt(json['input_tokens']);
    final output = _parseInt(json['output_tokens']);
    final total = _parseInt(json['total_tokens']);
    final cached = _parseInt(json['cache_read_tokens'] ?? json['cached_tokens']);
    final thinking = _parseInt(json['thinking_tokens']);
    final limit = json['context_window_limit'] != null ? _parseInt(json['context_window_limit']) : null;

    final resolvedTotal = total > 0 ? total : (input + output);

    return TokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: resolvedTotal,
      cacheReadTokens: cached,
      thinkingTokens: thinking,
      contextWindowLimit: limit != null && limit > 0 ? limit : null,
    );
  }

  static int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  bool get isEmpty =>
      inputTokens == 0 &&
      outputTokens == 0 &&
      totalTokens == 0 &&
      cacheReadTokens == 0 &&
      thinkingTokens == 0;

  double? get contextUsagePercent {
    if (contextWindowLimit == null || contextWindowLimit! <= 0) return null;
    return (totalTokens / contextWindowLimit!).clamp(0.0, 1.0);
  }

  TokenUsage operator +(TokenUsage other) {
    return TokenUsage(
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      totalTokens: totalTokens + other.totalTokens,
      cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
      thinkingTokens: thinkingTokens + other.thinkingTokens,
      contextWindowLimit: contextWindowLimit ?? other.contextWindowLimit,
    );
  }

  String formatCompact() {
    if (isEmpty) return 'Usage: N/A';
    final fmt = NumberFormat('#,###');
    final parts = <String>[
      'Input: ${fmt.format(inputTokens)}',
      'Output: ${fmt.format(outputTokens)}',
      'Total: ${fmt.format(totalTokens)}',
    ];
    if (cacheReadTokens > 0) {
      parts.add('Cached: ${fmt.format(cacheReadTokens)}');
    }
    return parts.join(' | ');
  }

  String formatShort() {
    if (isEmpty) return '0 tokens';
    if (totalTokens >= 1000000) {
      return '${(totalTokens / 1000000).toStringAsFixed(1)}M tokens';
    }
    if (totalTokens >= 1000) {
      return '${(totalTokens / 1000).toStringAsFixed(1)}k tokens';
    }
    return '$totalTokens tokens';
  }
}
