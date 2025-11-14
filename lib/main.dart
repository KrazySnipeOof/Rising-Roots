import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => RegenerativeState(),
      child: const RisingRootsApp(),
    ),
  );
}

class RisingRootsApp extends StatelessWidget {
  const RisingRootsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF264653));

    return MaterialApp(
      title: 'Rising Roots',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F5F2),
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme).apply(
              bodyColor: const Color(0xFF2D1E2F),
              displayColor: const Color(0xFF2D1E2F),
            ),
        appBarTheme: AppBarTheme(
          elevation: 0,
          backgroundColor: scheme.surface,
          foregroundColor: scheme.primary,
        ),
      ),
      home: const RisingRootsHome(),
    );
  }
}

class RisingRootsHome extends StatefulWidget {
  const RisingRootsHome({super.key});

  @override
  State<RisingRootsHome> createState() => _RisingRootsHomeState();
}

class _RisingRootsHomeState extends State<RisingRootsHome> {
  int _selectedIndex = 0;

  final List<_SectionDescriptor> _sections = [
    _SectionDescriptor(
      label: 'Pulse',
      icon: Icons.auto_graph_rounded,
      builder: (_) => const DashboardView(),
    ),
    _SectionDescriptor(
      label: 'Blueprints',
      icon: Icons.grid_view_rounded,
      builder: (_) => const BlueprintLibraryView(),
    ),
    _SectionDescriptor(
      label: 'Marketplace',
      icon: Icons.eco_rounded,
      builder: (_) => const MarketplaceView(),
    ),
    _SectionDescriptor(
      label: 'Network',
      icon: Icons.forum_rounded,
      builder: (_) => const NetworkPulseView(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showRail = constraints.maxWidth >= 900;
        final currentSection = _sections[_selectedIndex];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Rising Roots'),
            actions: const [
              _StatusChip(label: 'Beta Lab 02', icon: Icons.science_rounded),
              SizedBox(width: 8),
              _StatusChip(label: 'Carbon+ Certified', icon: Icons.verified_rounded),
              SizedBox(width: 16),
            ],
          ),
          body: Row(
            children: [
              if (showRail)
                NavigationRail(
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  leading: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: const Icon(Icons.spa_rounded),
                        ),
                        const SizedBox(height: 12),
                        const Text('Collective', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  destinations: _sections
                      .map(
                        (section) => NavigationRailDestination(
                          icon: Icon(section.icon),
                          label: Text(section.label),
                        ),
                      )
                      .toList(),
                ),
              Expanded(child: currentSection.builder(context)),
            ],
          ),
          bottomNavigationBar: showRail
              ? null
              : NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) => setState(() => _selectedIndex = index),
                  destinations: _sections
                      .map(
                        (section) => NavigationDestination(
                          icon: Icon(section.icon),
                          label: section.label,
                        ),
                      )
                      .toList(),
                ),
        );
      },
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RegenerativeState>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: [
              _HeroPanel(
                title: 'Rising Roots Lab',
                subtitle: 'Living blueprints for regenerative farming collectives.',
                highlight: 'Current experiment: Mycelial water routing pilot',
                metricLabel: 'Regenerative impact',
                metricValue: '${state.impactScore.toStringAsFixed(1)} pts',
                onRebalance: state.regeneratePulse,
              ),
              _AmbientPanel(
                soilReadings: state.soilReadings,
                regenRate: state.regenRate,
                carbonOffset: state.carbonOffset,
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final singleColumn = constraints.maxWidth < 900;
              return Flex(
                direction: singleColumn ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: singleColumn ? 0 : 2,
                    child: _InsightCard(
                      title: 'Soil vitality pulse',
                      trailing: IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        onPressed: state.regeneratePulse,
                      ),
                      child: SizedBox(
                        height: 260,
                        child: SoilPulseChart(readings: state.soilReadings),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    flex: 1,
                    child: _InsightCard(
                      title: 'Upcoming field rituals',
                      child: Column(
                        children: state.upcomingActions
                            .map(
                              (task) => ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                  child: Icon(task.icon, color: Theme.of(context).colorScheme.primary),
                                ),
                                title: Text(task.title),
                                subtitle: Text('${DateFormat.MMMd().format(task.when)} • ${task.location}'),
                                trailing: Text(task.owner),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class BlueprintLibraryView extends StatelessWidget {
  const BlueprintLibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RegenerativeState>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Regenerative blueprints',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text('Select a biome to spin up a field-ready activation kit.'),
          const SizedBox(height: 24),
          Wrap(
            spacing: 24,
            runSpacing: 24,
            children: state.blueprints
                .map(
                  (blueprint) => _BlueprintCard(
                    blueprint: blueprint,
                    onPinToggle: () => state.toggleBlueprintPin(blueprint),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class MarketplaceView extends StatelessWidget {
  const MarketplaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final listings = context.watch<RegenerativeState>().marketListings;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Commons marketplace',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('Soil intelligence, living amendments, and kinetic collaborations.'),
          const SizedBox(height: 24),
          ...listings.map(
            (listing) => Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(listing.icon, color: Theme.of(context).colorScheme.primary, size: 30),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(listing.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(listing.description),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(listing.creditLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(listing.delivery),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Activate'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NetworkPulseView extends StatelessWidget {
  const NetworkPulseView({super.key});

  @override
  Widget build(BuildContext context) {
    final threads = context.watch<RegenerativeState>().networkThreads;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mycelial network pulse',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('Conversations rippling through the Rising Roots guild.'),
          const SizedBox(height: 24),
          ...threads.map(
            (thread) => Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(thread.origin[0]),
                ),
                title: Text(thread.title),
                subtitle: Text('${thread.origin} • ${thread.summary}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('${thread.replies} replies'),
                    Text(thread.recencyLabel, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SoilPulseChart extends StatelessWidget {
  const SoilPulseChart({super.key, required this.readings});

  final List<SoilHealthReading> readings;

  @override
  Widget build(BuildContext context) {
    final spots = readings
        .map(
          (reading) => FlSpot(
            reading.date.month + (reading.date.day / 31),
            reading.organicMatter,
          ),
        )
        .toList();

    return LineChart(
      LineChartData(
        minY: 2,
        maxY: 8,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              reservedSize: 44,
              showTitles: true,
              getTitlesWidget: (value, _) => Text('${value.toStringAsFixed(1)}%'),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, _) {
                final monthIndex = value.clamp(1, 12).round();
                final label = DateFormat.MMM().format(DateTime(2000, monthIndex));
                return Text(label, style: const TextStyle(fontSize: 12));
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            barWidth: 4,
            color: Theme.of(context).colorScheme.primary,
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
            ),
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }
}

class _SectionDescriptor {
  const _SectionDescriptor({
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.highlight,
    required this.metricLabel,
    required this.metricValue,
    required this.onRebalance,
  });

  final String title;
  final String subtitle;
  final String highlight;
  final String metricLabel;
  final String metricValue;
  final VoidCallback onRebalance;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF274046), Color(0xFF335C67)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_fix_high_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(highlight, style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text(
            metricLabel.toUpperCase(),
            style: TextStyle(color: Colors.white.withOpacity(0.8), letterSpacing: 1.2),
          ),
          Text(
            metricValue,
            style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              foregroundColor: Colors.white,
            ),
            onPressed: onRebalance,
            icon: const Icon(Icons.bolt),
            label: const Text('Rebalance terrain'),
          ),
        ],
      ),
    );
  }
}

class _AmbientPanel extends StatelessWidget {
  const _AmbientPanel({
    required this.soilReadings,
    required this.regenRate,
    required this.carbonOffset,
  });

  final List<SoilHealthReading> soilReadings;
  final double regenRate;
  final double carbonOffset;

  @override
  Widget build(BuildContext context) {
    final latest = soilReadings.last;
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 12,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Field climate brief', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AmbientMetric(
                  label: 'Organic matter',
                  value: '${latest.organicMatter.toStringAsFixed(1)}%',
                  trend: regenRate,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _AmbientMetric(
                  label: 'Infiltration',
                  value: '${latest.infiltration.toStringAsFixed(1)} in/hr',
                  trend: -1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _AmbientMetric(
                  label: 'Carbon drawdown',
                  value: '${carbonOffset.toStringAsFixed(1)} t',
                  trend: 3.4,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: _AmbientMetric(
                  label: 'Biodiversity nodes',
                  value: '12 activated',
                  trend: 1.1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AmbientMetric extends StatelessWidget {
  const _AmbientMetric({
    required this.label,
    required this.value,
    required this.trend,
  });

  final String label;
  final String value;
  final double trend;

  @override
  Widget build(BuildContext context) {
    final color = trend >= 0 ? Colors.teal : Colors.deepOrange;
    final icon = trend >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 4),
              Text(
                '${trend >= 0 ? '+' : ''}${trend.toStringAsFixed(1)}%',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(right: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const Spacer(),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _BlueprintCard extends StatelessWidget {
  const _BlueprintCard({
    required this.blueprint,
    required this.onPinToggle,
  });

  final RegenerativeBlueprint blueprint;
  final VoidCallback onPinToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(blueprint.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: onPinToggle,
                icon: Icon(
                  blueprint.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: blueprint.isPinned ? Theme.of(context).colorScheme.primary : Colors.grey,
                ),
              ),
            ],
          ),
          Text('${blueprint.biome} • ${blueprint.duration} week sprint'),
          const SizedBox(height: 12),
          Text(blueprint.description),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: blueprint.focus.map((focus) => Chip(label: Text(focus))).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Carbon score: ${blueprint.carbonScore}'),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Spin up'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RegenerativeState extends ChangeNotifier {
  RegenerativeState();

  final _random = Random();

  final List<SoilHealthReading> _soilReadings = List.generate(
    6,
    (index) => SoilHealthReading(
      date: DateTime(2025, DateTime.january + index, 1 + index * 3),
      organicMatter: 3 + index * 0.7 + Random().nextDouble(),
      infiltration: 2 + index * 0.3 + Random().nextDouble(),
    ),
  );

  final List<RegenerativeBlueprint> _blueprints = [
    RegenerativeBlueprint(
      name: 'Dune Orchard',
      biome: 'Arid coast',
      description: 'Fog-net orchards that capture saline mist and redirect carbon-rich dew.',
      focus: const ['Fog nets', 'Agroforestry', 'Bioceramics'],
      duration: 8,
      carbonScore: 86,
    ),
    RegenerativeBlueprint(
      name: 'Lumen Valley',
      biome: 'Temperate highland',
      description: 'Light-bending terraces that wake soil microbes at sunrise.',
      focus: const ['Light wells', 'Mycelial mats', 'Contour guilds'],
      duration: 6,
      carbonScore: 92,
    ),
    RegenerativeBlueprint(
      name: 'Cloud Meadow',
      biome: 'Humid prairie',
      description: 'Breathable biofabric capturing humidity for slow-release irrigation.',
      focus: const ['Biofabric', 'Prairie guilds'],
      duration: 5,
      carbonScore: 78,
    ),
  ];

  final List<ActivationTask> _upcomingActions = [
    ActivationTask(
      title: 'Prime mycelial channels',
      location: 'Lab plot C',
      owner: 'Nia',
      icon: Icons.science_rounded,
      when: DateTime.now().add(const Duration(hours: 6)),
    ),
    ActivationTask(
      title: 'Deploy fog nets',
      location: 'Dune Orchard ridge',
      owner: 'Milo',
      icon: Icons.cloud_rounded,
      when: DateTime.now().add(const Duration(hours: 26)),
    ),
    ActivationTask(
      title: 'Biodiversity census',
      location: 'North basin',
      owner: 'Aria',
      icon: Icons.auto_awesome_rounded,
      when: DateTime.now().add(const Duration(days: 2)),
    ),
  ];

  final List<MarketListing> _marketListings = [
    MarketListing(
      title: 'Soil listening kit',
      description: 'Acoustic probes that translate microbial chatter into spectral maps.',
      creditLabel: '32 regen credits',
      delivery: 'Ships in 2 days',
      icon: Icons.graphic_eq_rounded,
    ),
    MarketListing(
      title: 'Biochar mist blend',
      description: 'High surface-area biochar suspended in aloe for foliar feeding.',
      creditLabel: '11 regen credits',
      delivery: 'Pickup: Lab 06',
      icon: Icons.local_florist_rounded,
    ),
    MarketListing(
      title: 'Commons residency',
      description: 'Residency slot for a neighboring farm to co-create carbon rituals.',
      creditLabel: 'Invite-only',
      delivery: 'Seasonal block',
      icon: Icons.handshake_rounded,
    ),
  ];

  final List<NetworkThread> _threads = [
    NetworkThread(
      title: 'Does anyone have wind data from ridge tunnels?',
      origin: 'Isla, Coastal Node',
      summary: 'Testing vented wind harps and need comparative baselines.',
      replies: 14,
      recencyLabel: '15m ago',
    ),
    NetworkThread(
      title: 'Microclover understory results',
      origin: 'Portland Collective',
      summary: 'Sharing 3-month water retention numbers + drone imagery.',
      replies: 32,
      recencyLabel: '1h ago',
    ),
    NetworkThread(
      title: 'Looking for carbon credit co-signers',
      origin: 'Kinship Farm',
      summary: 'Need partners for a 240-acre blended fiber grant.',
      replies: 9,
      recencyLabel: '1d ago',
    ),
  ];

  double _impactScore = 74;
  double _regenRate = 5.8;
  double _carbonOffset = 18.6;

  List<SoilHealthReading> get soilReadings => List.unmodifiable(_soilReadings);
  List<RegenerativeBlueprint> get blueprints => List.unmodifiable(_blueprints);
  List<ActivationTask> get upcomingActions => List.unmodifiable(_upcomingActions);
  List<MarketListing> get marketListings => List.unmodifiable(_marketListings);
  List<NetworkThread> get networkThreads => List.unmodifiable(_threads);
  double get regenRate => _regenRate;
  double get carbonOffset => _carbonOffset;
  double get impactScore => _impactScore;

  void regeneratePulse() {
    final delta = _random.nextDouble() * 6 - 3;
    _impactScore = (_impactScore + delta).clamp(60, 98);
    _regenRate = (_regenRate + _random.nextDouble()).clamp(3, 9);
    _carbonOffset = (_carbonOffset + _random.nextDouble()).clamp(15, 32);

    _soilReadings.removeAt(0);
    _soilReadings.add(
      SoilHealthReading(
        date: DateTime(
          _soilReadings.last.date.year,
          _soilReadings.last.date.month + 1,
          _soilReadings.last.date.day,
        ),
        organicMatter: _soilReadings.last.organicMatter + _random.nextDouble() * 0.4,
        infiltration: _soilReadings.last.infiltration + _random.nextDouble() * 0.2,
      ),
    );
    notifyListeners();
  }

  void toggleBlueprintPin(RegenerativeBlueprint blueprint) {
    blueprint.isPinned = !blueprint.isPinned;
    notifyListeners();
  }
}

class SoilHealthReading {
  SoilHealthReading({
    required this.date,
    required this.organicMatter,
    required this.infiltration,
  });

  final DateTime date;
  final double organicMatter;
  final double infiltration;
}

class RegenerativeBlueprint {
  RegenerativeBlueprint({
    required this.name,
    required this.biome,
    required this.description,
    required this.focus,
    required this.duration,
    required this.carbonScore,
    this.isPinned = false,
  });

  final String name;
  final String biome;
  final String description;
  final List<String> focus;
  final int duration;
  final int carbonScore;
  bool isPinned;
}

class ActivationTask {
  ActivationTask({
    required this.title,
    required this.location,
    required this.owner,
    required this.icon,
    required this.when,
  });

  final String title;
  final String location;
  final String owner;
  final IconData icon;
  final DateTime when;
}

class MarketListing {
  MarketListing({
    required this.title,
    required this.description,
    required this.creditLabel,
    required this.delivery,
    required this.icon,
  });

  final String title;
  final String description;
  final String creditLabel;
  final String delivery;
  final IconData icon;
}

class NetworkThread {
  NetworkThread({
    required this.title,
    required this.origin,
    required this.summary,
    required this.replies,
    required this.recencyLabel,
  });

  final String title;
  final String origin;
  final String summary;
  final int replies;
  final String recencyLabel;
}

