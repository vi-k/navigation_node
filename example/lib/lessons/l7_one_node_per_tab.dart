import 'package:flutter/material.dart';
import 'package:navigation_node/navigation_node.dart';

import '../lesson.dart';

/// Lesson 7: several nodes on one route, and the switch that tells them apart.
final oneNodePerTabLesson = Lesson(
  title: '7. One node per tab',
  summary: 'Every node on the route answers the same back — `enabled` says '
      'which one should',
  explanation: const [
    'An `IndexedStack` builds every tab and shows one, so a node per tab means '
        'several nodes standing on the same route at once. The route asks each '
        'of its `PopEntry`s and calls each of them back, so a single press '
        'unwinds every tab, the hidden ones included.',
    'Which tab is on screen is not something a node can find out: a hidden '
        'branch reads exactly as a shown one. The application knows, and '
        '`enabled` is where it says so.',
  ],
  instruction: 'push a page in tab A, switch to tab B, press System back, then '
      'come back to A. With the switch off, A has quietly lost its page — and '
      'the journal says when it went.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  static const _tabs = ['A', 'B'];

  /// The pages of the tabs, built once and kept.
  ///
  /// A node hands its navigator a fresh page list whenever its `child` is a new
  /// object, and the navigator then diffs its stack and reports it again. Held
  /// in a field, the subtree stays the same object across the rebuilds this
  /// lesson makes on every switch.
  late final List<Widget> _homes = [
    for (final name in _tabs) _TabHome(name: name),
  ];

  int _tab = 0;
  bool _wired = true;

  @override
  Widget build(BuildContext context) => Stage(
        label: 'one route, two nodes',
        child: Column(
          children: [
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text('Tab ${_tabs[i]}'),
                      selected: _tab == i,
                      onSelected: (_) => setState(() => _tab = i),
                    ),
                  ),
              ],
            ),
            SwitchListTile(
              value: _wired,
              onChanged: (value) => setState(() => _wired = value),
              title: const Text('enabled: i == the visible tab'),
              subtitle: Text(
                _wired
                    ? 'only the tab on screen answers the back'
                    : 'every node says enabled: true — all of them answer',
              ),
              dense: true,
            ),
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    NavigationNode(
                      enabled: !_wired || i == _tab,
                      child: _homes[i],
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _TabHome extends StatelessWidget {
  final String name;

  const _TabHome({required this.name});

  @override
  Widget build(BuildContext context) => NodeHome(
        title: 'tab $name',
        child: ScrollIfTight(
          child: PushButton(
            label: 'Push a page in tab $name',
            pageName: 'page of tab $name',
            builder: (context) => SamplePage(title: 'Pushed in tab $name'),
          ),
        ),
      );
}
