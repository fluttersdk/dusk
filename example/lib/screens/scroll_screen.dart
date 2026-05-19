import 'package:flutter/material.dart';

/// Scroll scenarios. Three regions:
///   1. Horizontal scroll strip of 20 cards (single-row swipe target).
///   2. Vertical ListView of 200 items (`dusk:scroll ref=<list>` deep
///      scrolling + `dusk:wait_for text='Item 150'` integration test).
///   3. CustomScrollView with slivers (mixed sliver kinds — header, grid,
///      list — exercise scroll plumbing beyond plain ListView).
class ScrollScreen extends StatelessWidget {
  const ScrollScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scroll'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Horizontal'),
              Tab(text: 'List 200'),
              Tab(text: 'Slivers'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_HorizontalStrip(), _LongList(), _SliverShowcase()],
        ),
      ),
    );
  }
}

class _HorizontalStrip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Swipe horizontally to scroll through 20 cards.'),
        ),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 20,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => Container(
              width: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Card ${i + 1}'),
            ),
          ),
        ),
      ],
    );
  }
}

class _LongList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 200,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => ListTile(
        leading: CircleAvatar(child: Text('${i + 1}')),
        title: Text('Item ${i + 1}'),
        subtitle: Text('Position $i in the list'),
        trailing: i % 7 == 0
            ? const Icon(Icons.star, color: Colors.amber)
            : null,
      ),
    );
  }
}

class _SliverShowcase extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 160,
          flexibleSpace: FlexibleSpaceBar(
            title: const Text('Sliver Header'),
            background: Container(color: Colors.indigo.shade100),
          ),
        ),
        SliverGrid.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: List.generate(
            12,
            (i) => Container(
              alignment: Alignment.center,
              color: Colors.indigo.shade50,
              child: Text('Grid ${i + 1}'),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => ListTile(title: Text('Sliver Item ${i + 1}')),
            childCount: 30,
          ),
        ),
      ],
    );
  }
}
