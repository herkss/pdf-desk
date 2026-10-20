import 'package:flutter/material.dart';

/// Horizontal toolbar that scrolls when the window is too narrow.
class ToolbarRow extends StatelessWidget {
  const ToolbarRow({super.key, required this.items, this.trailing = const []});
  final List<Widget> items;

  /// Always-visible widgets pinned to the right edge.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      color: const Color(0xFFFAFBFC),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(child: Row(children: items)),
            ),
          ),
          ...trailing,
        ],
      ),
    );
  }
}

class ToolSeparator extends StatelessWidget {
  const ToolSeparator({super.key});

  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 14, indent: 10, endIndent: 10, color: Color(0xFFD5D9DE));
}

/// Icon-over-label button, like classic document-management toolbars.
class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: ToolButtonFace(icon: icon, label: label, enabled: onPressed != null, active: active),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

class ToolButtonFace extends StatelessWidget {
  const ToolButtonFace({super.key, required this.icon, required this.label, this.enabled = true, this.active = false});

  final IconData icon;
  final String label;
  final bool enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = !enabled
        ? Colors.black26
        : active
        ? scheme.primary
        : Colors.black87;
    return Container(
      constraints: const BoxConstraints(minWidth: 54),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: active ? scheme.primaryContainer : null, borderRadius: BorderRadius.circular(6)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
