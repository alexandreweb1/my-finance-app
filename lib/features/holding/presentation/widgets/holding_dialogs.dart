import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/app_localizations.dart';
import '../../../../core/utils/cents.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/money_input_formatter.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../sharing/presentation/providers/sharing_provider.dart';
import '../../../workspaces/domain/workspace_entity.dart';
import '../../domain/holding_entities.dart';
import '../../domain/holding_math.dart';
import '../providers/holding_provider.dart';

/// The two write dialogs of the Holding: "novo sócio" and "novo aporte".
///
/// Both are deliberately *imperative* entry points (a function, not a widget):
/// the owner check and the "is a Holding even active" check have to happen
/// BEFORE anything is shown, so a collaborator never types a whole form only to
/// be told at save time that they cannot write.

// ─────────────────────────────────────────────────────────────────────────────
// Gate
// ─────────────────────────────────────────────────────────────────────────────

/// True when the active Carteira is a Holding AND the current user owns it.
///
/// Sócios and aportes are the Holding's identity: a shared collaborator can
/// read them (their own position included) but must never edit them, so this is
/// checked here and again by the Firestore rules. Explains itself with a
/// SnackBar rather than failing silently.
bool _ownsActiveHolding(BuildContext context, WidgetRef ref) {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final holding = ref.read(activeHoldingProvider);
  if (holding == null) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.holdingNotAHolding)));
    return false;
  }
  final uid = ref.read(authStateProvider).value?.id;
  if (uid == null || uid != holding.ownerId) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.holdingReadOnly)));
    return false;
  }
  return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// People with access to the Holding (for the "membro do app" picker)
// ─────────────────────────────────────────────────────────────────────────────

/// An app user who can be linked to a sócio: their uid plus the best label we
/// can resolve for them.
class _Person {
  final String uid;
  final String label;
  const _Person(this.uid, this.label);
}

/// Everyone with access to the active Holding, labelled.
///
/// The Carteira doc only stores uids, so the label is resolved from the two
/// sources the app actually has: the signed-in user's own profile, and the
/// accepted invitations of this master (which carry the invitee's email).
/// A uid we cannot resolve still renders — as the uid itself — because a row
/// the owner cannot identify is far better than a sócio they cannot create.
final _holdingPeopleProvider = Provider<List<_Person>>((ref) {
  final holding = ref.watch(activeHoldingProvider);
  if (holding == null) return const [];

  final me = ref.watch(authStateProvider).value;
  final emailByUid = <String, String>{};
  for (final inv in ref.watch(myCollaboratorsProvider).value ?? const []) {
    final uid = inv.collaboratorUserId;
    if (uid != null && uid.isNotEmpty) emailByUid[uid] = inv.inviteeEmail;
  }

  String labelFor(String uid) {
    if (me != null && uid == me.id) {
      final name = me.displayName?.trim() ?? '';
      if (name.isNotEmpty) return name;
      if (me.email.isNotEmpty) return me.email;
    }
    final email = emailByUid[uid];
    if (email != null && email.isNotEmpty) return email;
    return uid;
  }

  return [for (final uid in holding.memberUids) _Person(uid, labelFor(uid))];
});

// ─────────────────────────────────────────────────────────────────────────────
// Sócio dialog
// ─────────────────────────────────────────────────────────────────────────────

/// Where a sócio's identity comes from.
enum _SocioSource {
  /// An app user who already has access to this Carteira — linked, so they see
  /// their own position on their own device.
  appMember,

  /// Someone who does not use Fintab: a name the owner types. Counts exactly
  /// the same in every calculation.
  standalone,
}

/// Adds a sócio, or edits [member] when one is given. Owner-gated.
Future<void> showAddSocioDialog(
  BuildContext context,
  WidgetRef ref, {
  HoldingMemberEntity? member,
}) async {
  if (!_ownsActiveHolding(context, ref)) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _SocioDialog(member: member),
  );
}

class _SocioDialog extends ConsumerStatefulWidget {
  final HoldingMemberEntity? member;
  const _SocioDialog({this.member});

  @override
  ConsumerState<_SocioDialog> createState() => _SocioDialogState();
}

class _SocioDialogState extends ConsumerState<_SocioDialog> {
  final _name = TextEditingController();
  final _quota = TextEditingController();
  late DateTime _joinedAt;
  _SocioSource _source = _SocioSource.appMember;
  String? _selectedUid;
  bool _loading = false;

  bool get _isEditing => widget.member != null;

  @override
  void initState() {
    super.initState();
    final member = widget.member;
    final holding = ref.read(activeHoldingProvider);
    _name.text = member?.name ?? '';
    if (member != null && member.quotaBps > 0) {
      _quota.text = _percentText(member.quotaBps);
    }
    // The default that matters: a sócio registered today almost always took
    // part from the day the Carteira was born, and "today" would silently drop
    // them out of every expense already recorded.
    _joinedAt = member?.joinedAt ?? holding?.createdAt ?? DateTime.now();
    if (_joinedAt.isAfter(DateTime.now())) _joinedAt = DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _quota.dispose();
    super.dispose();
  }

  /// uids already linked to a sócio — including sócios who have left.
  ///
  /// Linking one app user to two sócios would show that person two different
  /// positions on their own phone with no way to tell which one is theirs, so
  /// the picker hides them; "pessoa sem conta" stays available as the escape
  /// hatch for a genuine second stake.
  Set<String> get _takenUids {
    final all = ref.watch(holdingMembersStreamProvider).value ?? const [];
    return {
      for (final m in all)
        if (m.memberUid != null && m.memberUid!.isNotEmpty) m.memberUid!,
    };
  }

  Future<void> _pickJoinedAt() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _joinedAt.isAfter(now) ? now : _joinedAt,
      firstDate: DateTime(2000),
      // No future joinedAt: it would exclude the sócio from expenses that
      // already exist and leave the owner hunting for the reason.
      lastDate: now,
    );
    if (picked != null) setState(() => _joinedAt = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _loading = true);

    final notifier = ref.read(holdingNotifierProvider.notifier);
    final member = widget.member;
    // Outside fixed mode the hand-set percentage is preserved untouched rather
    // than zeroed: switching the Holding to fixed mode later must not silently
    // wipe quotas the owner already typed.
    final bps = _isFixedMode
        ? (_bpsFromPercent(_quota.text) ?? 0)
        : (member?.quotaBps ?? 0);

    final bool ok;
    if (member == null) {
      final id = await notifier.addMember(
        name: name,
        memberUid: _source == _SocioSource.appMember ? _selectedUid : null,
        quotaBps: bps,
        joinedAt: _joinedAt,
      );
      ok = id != null;
    } else {
      ok = await notifier.updateMember(
        member.copyWith(name: name, quotaBps: bps, joinedAt: _joinedAt),
      );
    }

    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.holdingSaveError)));
      return;
    }
    Navigator.of(context).pop();
  }

  bool get _isFixedMode =>
      ref.watch(activeHoldingProvider)?.quotaMode == HoldingQuotaMode.fixed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final people = ref
        .watch(_holdingPeopleProvider)
        .where((p) => !_takenUids.contains(p.uid))
        .toList();
    final canPickAppMember = people.isNotEmpty;

    return AlertDialog(
      title:
          Text(_isEditing ? l10n.holdingEditPartner : l10n.holdingAddPartner),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The source choice only exists while creating: re-linking an
            // existing sócio to a different app user would rewrite who owns a
            // history that is already frozen into past rateios.
            if (!_isEditing) ...[
              // A Wrap of chips, not a SegmentedButton: two labelled segments
              // overflow inside an AlertDialog on a 320dp phone, and chips
              // wrap to a second line instead of painting overflow stripes.
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: Text(l10n.holdingSourceApp),
                    avatar: const Icon(Icons.person_rounded, size: 16),
                    selected: _source == _SocioSource.appMember,
                    onSelected: canPickAppMember
                        ? (_) =>
                            setState(() => _source = _SocioSource.appMember)
                        : null,
                  ),
                  ChoiceChip(
                    label: Text(l10n.holdingSourceOffline),
                    avatar: const Icon(Icons.person_outline_rounded, size: 16),
                    selected: _source == _SocioSource.standalone,
                    onSelected: (_) => setState(() {
                      _source = _SocioSource.standalone;
                      _selectedUid = null;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.holdingSourceHint,
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (_source == _SocioSource.appMember)
                canPickAppMember
                    ? DropdownButtonFormField<String>(
                        initialValue: _selectedUid,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.holdingPickAppMember,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final p in people)
                            DropdownMenuItem(
                              value: p.uid,
                              child: Text(p.label,
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (uid) => setState(() {
                          _selectedUid = uid;
                          // Prefill the name from whoever was picked so the
                          // sócio never lands with an empty label; the owner
                          // can still overwrite it with how they actually
                          // refer to that person.
                          final picked =
                              people.where((p) => p.uid == uid).toList();
                          if (picked.isNotEmpty) {
                            _name.text = picked.first.label;
                          }
                        }),
                      )
                    : Text(
                        l10n.holdingNoAppMembersLeft,
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant),
                      ),
              if (_source == _SocioSource.appMember) const SizedBox(height: 12),
            ],
            TextField(
              controller: _name,
              autofocus: _isEditing || _source == _SocioSource.standalone,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l10n.holdingPartnerName,
                hintText: 'Maria, João…',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _pickJoinedAt,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.holdingJoinedAt,
                  border: const OutlineInputBorder(),
                  helperText: l10n.holdingJoinedAtHint,
                  helperMaxLines: 4,
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded,
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(CurrencyFormatter.formatDate(
                        _joinedAt, ref.watch(dateLocaleProvider))),
                  ],
                ),
              ),
            ),
            if (_isFixedMode) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _quota,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.holdingQuotaPercent,
                  suffixText: '%',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _QuotaSumHint(
                validation: _liveValidation(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: (_loading || _name.text.trim().isEmpty) ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEditing ? l10n.save : l10n.create),
        ),
      ],
    );
  }

  /// The percentages as they WOULD BE if this dialog were saved: every other
  /// active sócio's stored quota plus whatever is typed here.
  ///
  /// Deliberately does NOT block saving when the total misses 100%. Blocking
  /// would deadlock the owner: to give a second sócio 50% the first must drop
  /// to 50% too, and every intermediate step is invalid. The app already
  /// handles the invalid state honestly — patrimony reads "indisponível" until
  /// the numbers add up — so the dialog warns and lets the edit through.
  FixedQuotaValidation _liveValidation() {
    final member = widget.member;
    final others = ref
        .watch(holdingActiveMembersProvider)
        .where((m) => m.id != member?.id);
    final bps = <String, int>{for (final m in others) m.id: m.quotaBps};
    // A sócio who already left is not part of the fixed-quota table, so their
    // percentage must not be counted into the live total either.
    if (member == null || member.isActive) {
      bps['__this__'] = _bpsFromPercent(_quota.text) ?? 0;
    }
    return validateFixedQuotas(bps);
  }
}

/// Live "do the percentages add up?" line under the quota field.
class _QuotaSumHint extends StatelessWidget {
  final FixedQuotaValidation validation;
  const _QuotaSumHint({required this.validation});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final total = _percentLabel(validation.sumBps);
    final delta = validation.deltaBps;
    final ok = validation.isValid;

    final String text;
    if (ok) {
      text = l10n.holdingQuotaSumOk(total);
    } else if (delta < 0) {
      text = l10n.holdingQuotaSumShort(total, _percentLabel(-delta));
    } else if (delta > 0) {
      text = l10n.holdingQuotaSumOver(total, _percentLabel(delta));
    } else {
      // sum is exactly 100% but a single quota is out of the 0–100% range.
      text = l10n.holdingInvalidFixedQuotas;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: ok ? const Color(0xFF10B981) : cs.error,
          ),
        ),
        if (!ok)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.holdingQuotaSumWarning,
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Aporte dialog
// ─────────────────────────────────────────────────────────────────────────────

/// Records an aporte (or a retirada) for a sócio. Owner-gated.
///
/// [memberId] pre-selects a sócio — the row the user tapped on the Holding
/// screen.
Future<void> showAddContributionDialog(
  BuildContext context,
  WidgetRef ref, {
  String? memberId,
}) async {
  if (!_ownsActiveHolding(context, ref)) return;
  final l10n = AppLocalizations.of(context);
  // An aporte belongs to somebody. Without a sócio there is nothing to record,
  // so say what to do instead of opening an empty picker.
  if (ref.read(holdingActiveMembersProvider).isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l10n.holdingNeedPartnerFirst)));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _ContributionDialog(memberId: memberId),
  );
}

class _ContributionDialog extends ConsumerStatefulWidget {
  final String? memberId;
  const _ContributionDialog({this.memberId});

  @override
  ConsumerState<_ContributionDialog> createState() =>
      _ContributionDialogState();
}

class _ContributionDialogState extends ConsumerState<_ContributionDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  DateTime _date = DateTime.now();
  String? _memberId;
  bool _isWithdrawal = false;
  bool _loading = false;

  static const _inColor = Color(0xFF10B981);
  static const _outColor = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    final members = ref.read(holdingActiveMembersProvider);
    // Only honour the pre-selection if that sócio is still active — otherwise
    // the dropdown would show a value that is not in its own item list.
    final wanted = widget.memberId;
    _memberId = members.any((m) => m.id == wanted)
        ? wanted
        : (members.isEmpty ? null : members.first.id);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The typed amount in centavos, always positive. Zero means "nothing usable
  /// typed" — the single conversion point from the app's text/double world.
  Cents get _cents => toCentsOr(moneyTextToDouble(_amount.text));

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final memberId = _memberId;
    final cents = _cents;
    if (memberId == null) return;
    // Zero moves no money and would still write a doc plus a transaction.
    if (cents == 0) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.invalidAmount)));
      return;
    }
    setState(() => _loading = true);
    final note = _note.text.trim();
    final id = await ref.read(holdingNotifierProvider.notifier).addContribution(
          memberId: memberId,
          // The sign IS the semantics: a retirada is the same doc with a
          // negative amount, which the equity math already folds correctly.
          amountCents: _isWithdrawal ? -cents : cents,
          date: _date,
          note: note.isEmpty ? null : note,
        );
    if (!mounted) return;
    setState(() => _loading = false);
    if (id == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.holdingSaveError)));
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final members = ref.watch(holdingActiveMembersProvider);
    final color = _isWithdrawal ? _outColor : _inColor;
    final symbol = ref.watch(currencySymbolProvider);

    return AlertDialog(
      title: Text(l10n.holdingAddContribution),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _memberId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.holdingPartner,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final m in members)
                  DropdownMenuItem(
                    value: m.id,
                    child: Text(m.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (id) => setState(() => _memberId = id),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [MoneyInputFormatter()],
              textAlign: TextAlign.center,
              onChanged: (_) => setState(() {}),
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: color),
              decoration: InputDecoration(
                hintText: '$symbol 0,00',
                hintStyle: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.35),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: color, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isWithdrawal,
              onChanged: (v) => setState(() => _isWithdrawal = v),
              title: Text(l10n.holdingWithdrawal,
                  style: const TextStyle(fontSize: 14)),
              subtitle: Text(l10n.holdingWithdrawalHint,
                  style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l10n.date,
                  border: const OutlineInputBorder(),
                ),
                child: Row(
                  children: [
                    Icon(Icons.event_rounded,
                        size: 18, color: cs.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Text(CurrencyFormatter.formatDate(
                        _date, ref.watch(dateLocaleProvider))),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.descriptionField,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            _ContributionPreview(
              memberId: _memberId,
              cents: _cents,
              date: _date,
              isWithdrawal: _isWithdrawal,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed:
              (_loading || _memberId == null || _cents == 0) ? null : _save,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

/// One line spelling out exactly what the Salvar button will record.
///
/// An aporte is money that changes every sócio's cota, so the user gets to read
/// the sentence — amount, who, when — before committing to it.
class _ContributionPreview extends ConsumerWidget {
  final String? memberId;
  final Cents cents;
  final DateTime date;
  final bool isWithdrawal;

  const _ContributionPreview({
    required this.memberId,
    required this.cents,
    required this.date,
    required this.isWithdrawal,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    if (memberId == null || cents == 0) return const SizedBox.shrink();

    final members = ref.watch(holdingActiveMembersProvider);
    final match = members.where((m) => m.id == memberId).toList();
    final name = match.isEmpty ? l10n.holdingPartner : match.first.name;
    final amount = ref.watch(currencyFormatterProvider)(toReais(cents));
    final day =
        CurrencyFormatter.formatDate(date, ref.watch(dateLocaleProvider));
    final text = isWithdrawal
        ? l10n.holdingWithdrawalPreview(amount, name, day)
        : l10n.holdingContributionPreview(amount, name, day);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isWithdrawal
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 16,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Percentage helpers (basis points ↔ text)
// ─────────────────────────────────────────────────────────────────────────────

/// Parses "33,33" / "33.33" / "33" into basis points, or null when it is not a
/// usable percentage.
///
/// Rejects non-finite and out-of-range values before rounding: `(double.
/// infinity * 100).round()` throws, and a quota outside 0–100% is meaningless.
int? _bpsFromPercent(String text) {
  final cleaned = text.trim().replaceAll('%', '').replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || !value.isFinite || value < 0 || value > 100) return null;
  return (value * 100).round();
}

/// Basis points as the digits of a percentage field ("5000" → "50,00").
String _percentText(int bps) =>
    (bps / 100).toStringAsFixed(2).replaceAll('.', ',');

/// Basis points as a label ("5000" → "50,00%").
String _percentLabel(int bps) => '${_percentText(bps)}%';
