import 'package:flutter/material.dart';

class CustomProgressIndicator extends StatefulWidget {
  final double value; // 0.0 to 1.0
  final double height;
  final double? width;
  final Color backgroundColor;
  final Color progressColor;
  final Color? borderColor;
  final double borderWidth;
  final double borderRadius;
  final Duration animationDuration;
  final Curve animationCurve;
  final bool showLabel;
  final TextStyle? labelStyle;

  const CustomProgressIndicator({
    Key? key,
    required this.value,
    this.height = 12,
    this.width,
    this.backgroundColor = Colors.black,
    this.progressColor = Colors.amber,
    this.borderColor = Colors.amberAccent,
    this.borderWidth = 1.5,
    this.borderRadius = 8,
    this.animationDuration = const Duration(milliseconds: 800),
    this.animationCurve = Curves.easeOutCubic,
    this.showLabel = false,
    this.labelStyle,
  }) : super(key: key);

  @override
  State<CustomProgressIndicator> createState() =>
      _CustomProgressIndicatorState();
}

class _CustomProgressIndicatorState extends State<CustomProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _setupAnimation();
  }

  void _setupAnimation() {
    _animation = Tween<double>(begin: 0, end: widget.value).animate(
      CurvedAnimation(
          parent: _animationController, curve: widget.animationCurve),
    );
    _animationController.forward();
  }

  @override
  void didUpdateWidget(CustomProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _animationController.reset();
      _setupAnimation();
      _animationController.forward();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              border: Border.all(
                color: widget.borderColor ?? Colors.transparent,
                width: widget.borderWidth,
              ),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            child: Stack(
              children: [
                // Shimmer effect (optional)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              widget.progressColor.withOpacity(0.3),
                              widget.progressColor,
                              widget.progressColor.withOpacity(0.3),
                            ],
                            stops: [
                              (_animationController.value - 0.2)
                                  .clamp(0.0, 1.0),
                              _animationController.value,
                              (_animationController.value + 0.2)
                                  .clamp(0.0, 1.0),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Progress fill
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return FractionallySizedBox(
                      widthFactor: _animation.value,
                      heightFactor: 1.0,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: BoxDecoration(
                          color: widget.progressColor,
                          borderRadius: BorderRadius.circular(
                            widget.borderRadius - widget.borderWidth,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        // Optional label
        if (widget.showLabel)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Text(
                  '${(_animation.value * 100).toStringAsFixed(0)}%',
                  style: widget.labelStyle ??
                      Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                );
              },
            ),
          ),
      ],
    );
  }
}

// ============================================
// USAGE EXAMPLES
// ============================================

class ProgressIndicatorExamples extends StatefulWidget {
  const ProgressIndicatorExamples({Key? key}) : super(key: key);

  @override
  State<ProgressIndicatorExamples> createState() =>
      _ProgressIndicatorExamplesState();
}

class _ProgressIndicatorExamplesState extends State<ProgressIndicatorExamples> {
  double _progress = 0.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom Progress Indicator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Example 1: Default blue progress bar
            Text(
              'Basic Progress Bar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            CustomProgressIndicator(value: _progress),
            const SizedBox(height: 32),

            // Example 2: With label
            Text(
              'With Percentage Label',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            CustomProgressIndicator(
              value: _progress,
              showLabel: true,
            ),
            const SizedBox(height: 32),

            // Example 3: Thick with custom colors
            Text(
              'Thick with Custom Colors',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            CustomProgressIndicator(
              value: _progress,
              height: 18,
              backgroundColor: Colors.grey.shade300,
              progressColor: Colors.green.shade400,
              borderColor: Colors.green.shade700,
              borderRadius: 12,
              borderWidth: 2,
              showLabel: true,
            ),
            const SizedBox(height: 32),

            // Example 4: Orange variant
            Text(
              'Orange Variant',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            CustomProgressIndicator(
              value: _progress,
              height: 14,
              backgroundColor: Colors.amber.shade100,
              progressColor: Colors.amber.shade400,
              borderColor: Colors.amber.shade700,
              borderRadius: 10,
              showLabel: true,
            ),
            const SizedBox(height: 32),

            // Example 5: Gradient effect
            Text(
              'Purple with Border',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            CustomProgressIndicator(
              value: _progress,
              height: 16,
              backgroundColor: Colors.purple.shade50,
              progressColor: Colors.purple.shade400,
              borderColor: Colors.purple.shade600,
              borderWidth: 2,
              borderRadius: 8,
              showLabel: true,
            ),
            const SizedBox(height: 48),

            // Slider to control progress
            Text(
              'Control Progress',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Slider(
              value: _progress,
              onChanged: (value) {
                setState(() {
                  _progress = value;
                });
              },
              divisions: 100,
              label: '${(_progress * 100).toStringAsFixed(0)}%',
            ),
          ],
        ),
      ),
    );
  }
}
