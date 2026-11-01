import 'package:flutter/material.dart';

import 'theme.dart';

/// Yüzey: ince çerçeveli, gölgesiz kutu. Kartlarda gölge yerine çizgi kullanılır.
class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.radius = Radii.md,
    this.color = AppColors.surface,
    this.borderColor = AppColors.line,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;
  final Color borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return content;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          highlightColor: Colors.white10,
          child: content,
        ),
      ),
    );
  }
}

/// Bölüm başlığı: küçük, aralıklı büyük harf.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm, top: Insets.sm),
      child: Row(
        children: [
          Text(text.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Kimlik görseli. Fotoğraf yokken pubkey'den türeyen renkli baş harf gösterir.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.seed,
    this.label,
    this.imageUrl,
    this.size = 40,
    this.ring = false,
  });

  final String seed;
  final String? label;
  final String? imageUrl;
  final double size;
  final bool ring;

  static const _palette = <Color>[
    Color(0xFFFF6B35),
    Color(0xFF7C6BF5),
    Color(0xFF2DBE8C),
    Color(0xFFE0577F),
    Color(0xFF4C9AFF),
    Color(0xFFC9A227),
  ];

  static Color colorFor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(seed);
    final initial = (label?.trim().isNotEmpty ?? false)
        ? label!.trim().characters.first.toUpperCase()
        : '?';

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(
          color: ring ? color.withValues(alpha: 0.55) : AppColors.line,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
    );

    final url = imageUrl;
    if (url == null || url.isEmpty || !url.startsWith('http')) return fallback;

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: color.withValues(alpha: 0.16),
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Center(
            child: Text(
              initial,
              style: TextStyle(
                color: color,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : fallback,
        ),
      ),
    );
  }
}

/// Hikâye sırasındaki halkalı avatar. [active] ise turuncu degradeli çerçeve,
/// değilken nötr gri çerçeve kullanılır (Instagram mantığı, bizim paletimiz).
class StoryItem extends StatelessWidget {
  const StoryItem({
    super.key,
    required this.seed,
    required this.label,
    this.imageUrl,
    this.active = true,
    this.isMe = false,
    this.onTap,
    this.onAdd,
  });

  final String seed;
  final String label;
  final String? imageUrl;
  final bool active;
  final bool isMe;
  final VoidCallback? onTap;

  /// "Sen" halkasındaki + rozetine dokununca çalışır (hikâye ekle).
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    const avatarSize = 56.0;
    final inner = Avatar(seed: seed, label: label, imageUrl: imageUrl, size: avatarSize);

    return SizedBox(
      width: 76,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: active
                    ? const LinearGradient(
                        begin: Alignment.bottomLeft,
                        end: Alignment.topRight,
                        colors: [Color(0xFFFF6B35), Color(0xFFE0577F)],
                      )
                    : null,
                color: active ? null : AppColors.line,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.background,
                ),
                child: isMe
                    ? Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomRight,
                        children: [
                          inner,
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: GestureDetector(
                              onTap: onAdd,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: AppColors.background, width: 2),
                                ),
                                child: const Icon(Icons.add,
                                    size: 12, color: AppColors.accentInk),
                              ),
                            ),
                          ),
                        ],
                      )
                    : inner,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bağlantı durumunu gösteren nokta + etiket.
class ConnectionBadge extends StatelessWidget {
  const ConnectionBadge({super.key, required this.connected, this.label});

  final bool connected;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = connected ? AppColors.online : AppColors.textFaint;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: connected
                ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label ?? (connected ? 'Bağlı' : 'Bağlantı yok'),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: connected ? AppColors.textMuted : AppColors.textFaint,
              ),
        ),
      ],
    );
  }
}

/// İkon + başlık + açıklama. Boş listelerde kullanılır.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xxl,
        vertical: Insets.huge,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.line),
            ),
            child: Icon(icon, size: 24, color: AppColors.textFaint),
          ),
          const SizedBox(height: Insets.lg),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: Insets.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: Insets.lg),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Küçük etiket (chip). Seçili olduğunda vurgu rengini alır.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.selected = false, this.onTap});

  final String text;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent : AppColors.surface,
      borderRadius: Radii.pill,
      child: InkWell(
        borderRadius: Radii.pill,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: Radii.pill,
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.line,
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.accentInk : AppColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bölüm başlığı ile ayrılmış satır listesi (ayarlar, menüler).
class RowsGroup extends StatelessWidget {
  const RowsGroup({super.key, required this.children, this.label});

  final List<Widget> children;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) SectionLabel(label!),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class RowItem extends StatelessWidget {
  const RowItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? AppColors.offline : AppColors.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? AppColors.offline : AppColors.textMuted),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(color: color, fontSize: 14.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// Üst çubuk: büyük başlık + sağda eylem alanı.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.headlineSmall),
                    if (subtitle != null)
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          ?bottom,
        ],
      ),
    );
  }
}

/// İkonlu, dairesel küçük buton.
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final Widget button = Material(
      color: filled ? AppColors.accent : AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            icon,
            size: 18,
            color: filled ? AppColors.accentInk : AppColors.textMuted,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// Gönderi görseli — medya sunucusundan (`imeta`) gelen adresi basar.
class PostImage extends StatelessWidget {
  const PostImage({super.key, required this.url, this.height = 280});

  final String url;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: Radii.card,
      child: Image.network(
        url,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          height: 72,
          alignment: Alignment.center,
          color: AppColors.surface,
          child: const Icon(Icons.broken_image_outlined,
              color: AppColors.textFaint),
        ),
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : Container(
                height: height,
                alignment: Alignment.center,
                color: AppColors.surface,
                child: const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
      ),
    );
  }
}
