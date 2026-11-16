import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:resit/sites/adfs/auth_service.dart';
import 'package:resit/core/auth/session_controller.dart';
import 'package:resit/core/providers.dart';
import 'package:resit/core/ui/app_theme.dart';
import 'package:resit/core/ui/feedback.dart';
import 'package:resit/core/widgets/auth_gate.dart';
import 'package:resit/core/widgets/grade_privacy.dart';
import 'package:resit/core/widgets/mfa_card.dart';
import 'package:resit/core/widgets/panels.dart';
import 'package:resit/core/widgets/thumb_bar.dart';
import 'package:resit/features/exams/presentation/academic_progress_screen.dart';
import 'package:resit/core/widgets/desktop.dart';
import 'package:resit/features/exams/domain/exam_results.dart';

/// Exam results from in4SIT: opens on the latest term's result slip; the
/// term picker in the bottom bar switches terms.
class ExamResultsScreen extends StatelessWidget {
  /// Opened from Academic progress: its charts button goes back there
  /// instead of opening another copy.
  final bool fromProgress;
  const ExamResultsScreen({super.key, this.fromProgress = false});

  @override
  Widget build(BuildContext context) =>
      AuthGate(title: 'Exam results', builder: (_) => _ExamResults(fromProgress: fromProgress));
}

class _ExamResults extends ConsumerStatefulWidget {
  final bool fromProgress;
  const _ExamResults({this.fromProgress = false});

  @override
  ConsumerState<_ExamResults> createState() => _ExamResultsScreenState();
}

class _ExamResultsScreenState extends ConsumerState<_ExamResults> {
  List<ExamTerm>? _terms;
  ExamTerm? _term;
  ExamResults? _results;
  Object? _error;
  bool _loading = false;
  MfaChallenge? _challenge;

  /// A newer term skipped on opening because its results aren't out yet.
  String? _skippedTerm;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<T> _withSession<T>(Future<T> Function() task) => withSignInRetry(ref, task);

  void _onChallenge(MfaChallenge c) {
    if (mounted) setState(() => _challenge = c);
  }

  /// Loads the terms (if needed) and the picked term's slip, latest by default.
  Future<void> _load({ExamTerm? term, bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (term != null) _term = term;
    });
    final service = ref.read(examServiceProvider);
    try {
      final cached = _terms;
      final List<ExamTerm> terms;
      if (cached == null || refresh) {
        terms = await _withSession(() => service.terms(onMfaChallenge: _onChallenge));
        if (!mounted) return;
        setState(() => _terms = terms);
      } else {
        terms = cached;
      }
      if (terms.isEmpty) {
        setState(() => _results = null);
        return;
      }
      final current = _term;
      var pick =
          current == null ? terms.first : terms.firstWhere((t) => t.name == current.name, orElse: () => terms.first);
      setState(() {
        _term = pick;
        _skippedTerm = null;
      });
      var results = await _withSession(() => service.results(pick, refresh: refresh, onMfaChallenge: _onChallenge));

      // On opening, if the newest term isn't released yet, show the most
      // recent term that is (looking back up to two terms).
      if (current == null && results.notReleased) {
        final skipped = pick.name;
        for (final older in terms.skip(terms.indexOf(pick) + 1).take(2)) {
          final r = await _withSession(() => service.results(older, onMfaChallenge: _onChallenge));
          if (!r.notReleased) {
            pick = older;
            results = r;
            if (mounted) setState(() => _skippedTerm = skipped);
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          _term = pick;
          _results = results;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _challenge = null;
        });
      }
    }
  }

  Future<void> _pickTerm() async {
    final terms = _terms;
    if (terms == null || terms.isEmpty) return;
    final picked = await showChoiceSheet<ExamTerm>(
      context,
      icon: Icons.event_note_outlined,
      title: 'Choose a term',
      choices: [
        // The term on screen is ticked, not just coloured.
        for (final t in terms)
          SheetChoice(t, t.name, primary: t.name == _term?.name, icon: t.name == _term?.name ? Icons.check : null),
      ],
    );
    if (picked != null && picked.name != _term?.name) _load(term: picked);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      appBar: thumbAppBar('Exam results', subtitle: 'Result slip for each term, from in4SIT'),
      bottomNavigationBar: ThumbBar(
        child: Row(
          // Fill the bar's height, so every control is the same size.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FilledButton.tonal(
                onPressed: _loading || (_terms?.isEmpty ?? true) ? null : _pickTerm,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text(_term?.name ?? 'Term', overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 4),
                    const Icon(Icons.expand_more),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            const GradeVisibilityButton(inBar: true),
            const SizedBox(width: 8),
            // To the charts of every term (Academic progress links back here).
            ThumbIconButton(
              tooltip: 'Charts of every term',
              icon: Icons.insights_outlined,
              onPressed: () => widget.fromProgress
                  ? Navigator.pop(context)
                  : Navigator.push(context, MaterialPageRoute(builder: (_) => const AcademicProgressScreen())),
            ),
            const SizedBox(width: 8),
            ThumbIconButton(tooltip: 'Refresh', icon: Icons.refresh, onPressed: _loading ? null : () => _load(refresh: true)),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final session = ref.watch(sessionControllerProvider);
    final challenge = _challenge ?? (session.phase == SessionPhase.signingIn ? session.challenge : null);

    if (_loading && challenge != null) {
      return Center(
          child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: MfaCard(challenge: challenge)));
    }
    if (_error != null && _results == null) {
      return MessageView(
        icon: Icons.cloud_off,
        tone: Tone.danger,
        title: "Couldn't load your results",
        message: friendlyError(_error!),
        detail: errorDetail(_error!),
        action: FilledButton.icon(
          onPressed: () => _load(refresh: true),
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    final results = _results;
    if (results == null) {
      if (_loading) {
        return const MessageView(
          icon: Icons.grading_outlined,
          title: 'Getting your results…',
          message: 'From in4SIT. This can take a few seconds.',
          action: SizedBox(width: 160, child: LinearProgressIndicator()),
        );
      }
      return const MessageView(icon: Icons.grading_outlined, title: 'No results yet');
    }

    if (results.notReleased) {
      final terms = _terms ?? const <ExamTerm>[];
      final i = terms.indexWhere((t) => t.name == results.term.name);
      final previous = i >= 0 && i + 1 < terms.length ? terms[i + 1] : null;
      return MessageView(
        icon: Icons.hourglass_empty,
        title: 'Not released yet',
        message: 'Results for ${results.term.name} haven\'t been released. Check back after the release date.',
        action: previous == null || _loading
            ? null
            : FilledButton.tonalIcon(
                onPressed: () => _load(term: previous),
                icon: const Icon(Icons.history),
                label: Text('Show ${previous.name}'),
              ),
      );
    }

    return Column(
      children: [
        RefreshStrip(active: _loading),
        if (_skippedTerm != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 0),
            child: StatusBanner(
              tone: Tone.info,
              icon: Icons.hourglass_empty,
              title: 'Results for $_skippedTerm aren\'t out yet',
              message: 'Showing ${results.term.name}.',
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, 0),
            child: StatusBanner(
              tone: Tone.warning,
              icon: Icons.cloud_off,
              title: "Couldn't refresh",
              message: friendlyError(_error!),
              action: TextButton(onPressed: () => _load(refresh: true), child: const Text('Try again')),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(refresh: true),
            child: _ResultSlip(results: results),
          ),
        ),
      ],
    );
  }
}

class _ResultSlip extends ConsumerWidget {
  final ExamResults results;
  const _ResultSlip({required this.results});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Grades and GPAs stay hidden until the user taps the eye.
    final visible = ref.watch(gradesVisibleProvider);
    final muted = theme.colorScheme.onSurfaceVariant;
    final graded = results.courses.where((c) => !c.inProgress).toList();
    final credits = graded.fold<double>(0, (sum, c) => sum + (double.tryParse(c.credits) ?? 0));
    final standing = results.value('Academic Standing');

    if (results.courses.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          MessageView(
            icon: Icons.help_outline,
            title: "Couldn't read this result slip",
            message: 'in4SIT showed something the app doesn\'t recognise.',
            detail: results.pageText?.substring(0, results.pageText!.length.clamp(0, 400)),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.page, 8, Space.page, Space.section),
      children: [
        Text(results.heading, style: theme.textTheme.titleLarge),
        if (results.value('Programme') case final programme?)
          Text(programme, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _stat('Trimester GPA', results.value('Trimester GPA'), visible)),
              const SizedBox(width: Space.card),
              Expanded(child: _stat('Cumulative GPA', results.value('Cumulative GPA'), visible)),
            ],
          ),
        ),
        if (visible && standing != null && standing != '-') ...[
          const SizedBox(height: 8),
          StatusPill(label: 'Academic standing: $standing', tone: Tone.info),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Courses', style: theme.textTheme.titleMedium)),
            Text(
              '${results.courses.length} courses'
              '${credits > 0 ? ' · ${credits == credits.roundToDouble() ? credits.round() : credits} credits graded' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final c in results.courses)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: _CourseCard(course: c, hidden: !visible)),
        if (results.note != null) ...[
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: muted),
              const SizedBox(width: 8),
              Expanded(child: Text(results.note!, style: theme.textTheme.bodySmall?.copyWith(color: muted))),
            ],
          ),
        ],
        if (results.details.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Slip details'),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                for (final (label, value) in results.details)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                        ),
                        Expanded(child: Text(value)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A GPA as a highlighted stat tile (value over label, as on Home and
/// Academic progress), hidden until the user shows grades.
Widget _stat(String label, String? value, bool visible) => StatTile(
      tinted: true,
      value: !visible
          ? hiddenValue
          : value == null || value.isEmpty
              ? '–'
              : value,
      caption: label,
      semanticsLabel: visible ? null : '$label, hidden',
    );

class _CourseCard extends StatelessWidget {
  final CourseResult course;

  /// Grade and grade points covered, and the badge left uncoloured so its
  /// colour doesn't give the grade away.
  final bool hidden;
  const _CourseCard({required this.course, this.hidden = false});

  /// Colour by grade band: A greens, B blues, C/D ambers, F red, others grey.
  Tone _tone() {
    final g = course.grade.toUpperCase();
    if (g.startsWith('A') || g == 'PASS' || g == 'P') return Tone.success;
    if (g.startsWith('B')) return Tone.info;
    if (g.startsWith('C') || g.startsWith('D')) return Tone.warning;
    if (g.startsWith('F')) return Tone.danger;
    return Tone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (bg, fg) = (hidden ? Tone.neutral : _tone()).colors(theme.colorScheme);
    final facts = [
      course.code,
      if (course.credits.isNotEmpty) '${course.credits} credits',
      if (!hidden && !course.inProgress && course.gradePoints.isNotEmpty) '${course.gradePoints} grade points',
      if (course.remark.isNotEmpty) course.remark,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Semantics(
              label: course.inProgress
                  ? 'In progress'
                  : hidden
                      ? 'Grade hidden'
                      : 'Grade ${course.grade}',
              excludeSemantics: true,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                // A longer grade (e.g. "Pass") shrinks to fit on one line.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    course.grade.isEmpty
                        ? '–'
                        : hidden && !course.inProgress
                            ? hiddenValue
                            : course.grade,
                    maxLines: 1,
                    style: theme.textTheme.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(facts.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (course.inProgress) ...[
                    const SizedBox(height: 4),
                    const StatusPill(label: 'In progress', tone: Tone.neutral, icon: Icons.hourglass_bottom),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
