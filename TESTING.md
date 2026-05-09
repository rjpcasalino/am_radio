# Tests for am_radio

This directory contains tests for the am_radio project.

## Running Perl Script Tests

The Perl script tests are in the `t/` directory and use the standard Perl `Test::More` framework.

```bash
cd t
perl 01-basic.t
```

Or run all tests with `prove`:

```bash
prove -v t/
```

### Perl Test Coverage

- `01-basic.t`: Basic sanity tests
  - Checks script exists and is readable
  - Verifies syntax is correct
  - Tests help output
  - Verifies verbose flag works

## Running Flutter Tests

The Flutter mobile app tests are in the `mobile/test/` directory.

```bash
cd mobile
flutter test
```

### Flutter Test Coverage

- `services_test.dart`: Unit tests for PlayerService
  - Tests initial state
  - Tests lo-fi filter toggle
  - Tests stop() safety
  - Tests Station model creation

- `station_repository_test.dart`: Unit tests for StationRepository
  - Tests save/remove operations
  - Tests duplicate detection
  - Tests isSaved() method

- `settings_service_test.dart`: Unit tests for SettingsService
  - Tests initial minimalMode defaults to false
  - Tests load() reads from SharedPreferences
  - Tests setMinimalMode() updates and persists values
  - Tests notifyListeners is called on changes
  - 7 comprehensive tests covering performance mode toggle

- `log_service_test.dart`: Tests for LogService and LogViewerScreen
  - LogService unit tests:
    - Tests log entry addition and limiting (max 500 entries)
    - Tests clear() functionality
    - Tests export() formatting
  - LogViewerScreen widget tests:
    - Tests screen renders without crashing
    - Tests display of log entries with correct severity levels
    - Tests copy and clear button functionality
    - Tests "No logs yet" empty state

- `home_screen_widget_test.dart`: Widget tests for HomeScreen
  - Tests widget renders without crashing
  - Tests transport controls are present
  - Tests "off air" message when not playing
  - Tests TUNE label in default mode

## Test Requirements

### Perl Tests
- Perl 5.14+ (for JSON::PP)
- Test::More (core module)

### Flutter Tests
- Flutter SDK 3.16.0+
- flutter_test package (included in SDK)

## Adding New Tests

### Perl
Add new test files to the `t/` directory following the naming convention `NN-description.t`.

### Flutter
Add new test files to `mobile/test/` following Flutter test conventions.

## CI/CD Integration

These tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Test Perl script
  run: prove -v t/

- name: Test Flutter app
  run: |
    cd mobile
    flutter test
```
