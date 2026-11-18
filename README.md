# Quick Timer for DMS

Quick Timer adds countdown timers, clock alarms, and a stopwatch to Dux Modular Shell (DMS). Active timers appear in the bar, and an alert notifies you when a timer or alarm finishes.

## Requirements

- DMS 1.5.0 or newer

## Install

Clone the repository into your DMS plugins directory:

```bash
git clone https://github.com/mudabbir-abbas/DuxTimer.git ~/.config/dms/plugins/DuxTimer
```

In DMS, open **Settings → Plugins**, scan for plugins, and enable **Quick Timer**. Add its widget to your bar if you want the active timer pill to appear there.

To update the plugin later, run:

```bash
dms plugins update duxTimer
```

## Use from the launcher

Open the launcher and type the `quick` trigger followed by an action:

```text
quick timer 10
quick timer 1h 20m tea
quick alarm 7:30AM
quick stopwatch
```

A bare timer number means minutes. You can also use units such as `h`, `m`, and `s`. Add text after a timer duration or alarm time to label it.

While a timer is active, the launcher offers controls to pause or resume it, add one minute, or cancel it. Stopwatch controls include pause/resume, lap, and reset. You can also open the bar pill to use the controls.

## Settings

In **Settings → Plugins → Quick Timer**, you can:

- Turn the completion sound on or off.
- Set how long a finished timer stays in the bar before it is dismissed. Set this to `0` to keep it visible until you dismiss it.

## License

Quick Timer is licensed under the MIT License. See [LICENSE](LICENSE).
