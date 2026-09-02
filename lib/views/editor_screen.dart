        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeColor: Colors.amber.shade400,
          title: const Text('Noise cancellation (background audio)'),
          subtitle: Text(
            controller.backgroundAudioPath == null
                ? 'Add background audio above first to enable this'
                : "Reduces hiss/hum in the background audio track you added "
                    "- has no effect on the clips' own sound",
          ),
          value: controller.noiseCancellationEnabled,
          onChanged: controller.backgroundAudioPath == null
              ? null
              : controller.setNoiseCancellation,
        ),
        const SizedBox(height: 8),
        Text(
            'Volume boost (background audio): ${controller.volumePercent.round()}%'),
        Slider(
          activeColor: Colors.amber.shade400,
          value: controller.volumePercent,
          min: 100,
          max: 300,
          divisions: 20,
          label: '${controller.volumePercent.round()}%',
          onChanged: controller.backgroundAudioPath == null
              ? null
              : controller.setVolumePercent,
          onChangeEnd: controller.backgroundAudioPath == null
              ? null
              : (_) => controller.persistProject(),
        ),
