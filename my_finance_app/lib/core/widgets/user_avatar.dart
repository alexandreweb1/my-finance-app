import 'package:flutter/material.dart';

/// CircleAvatar that shows [photoUrl] when available, falling back to
/// [initials] text if the image fails to load or is absent.
class UserAvatar extends StatefulWidget {
  final String? photoUrl;
  final String initials;
  final double radius;
  final Color backgroundColor;
  final TextStyle textStyle;

  const UserAvatar({
    super.key,
    required this.photoUrl,
    required this.initials,
    required this.radius,
    required this.backgroundColor,
    required this.textStyle,
  });

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  bool _imageError = false;

  @override
  void didUpdateWidget(UserAvatar old) {
    super.didUpdateWidget(old);
    // Reset error state when URL changes
    if (old.photoUrl != widget.photoUrl) {
      _imageError = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = widget.photoUrl?.isNotEmpty == true && !_imageError;
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: widget.backgroundColor,
      backgroundImage: hasPhoto ? NetworkImage(widget.photoUrl!) : null,
      onBackgroundImageError: hasPhoto
          ? (_, __) {
              if (mounted) setState(() => _imageError = true);
            }
          : null,
      child: !hasPhoto
          ? Text(widget.initials, style: widget.textStyle)
          : null,
    );
  }
}
