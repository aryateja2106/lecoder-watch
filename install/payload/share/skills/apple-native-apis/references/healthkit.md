# HealthKit (iOS, watchOS)

HealthKit is gated twice and both gates are silent. First the
`com.apple.developer.healthkit` entitlement (`entitlements: path:` on the target in
`project.yml`; on a watchOS target it must be on the watch target itself): without it
`requestAuthorization(toShare:read:)` completes with `success == false` and
`HKError.errorAuthorizationDenied`, and nothing you write after that ever runs. Second
`NSHealthShareUsageDescription` (and `NSHealthUpdateUsageDescription` if you write),
which only controls the prompt's text. Verify with `codesign -d --entitlements -` on the
built app before calling the feature done.

```swift
import HealthKit

let store = HKHealthStore()
guard HKHealthStore.isHealthDataAvailable() else { /* iPad without Health: say so in the UI */ }
let read: Set<HKObjectType> = [
    HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned),
    HKQuantityType(.stepCount), HKQuantityType(.heartRate),
    HKCategoryType(.sleepAnalysis), HKObjectType.workoutType(),
]
try await store.requestAuthorization(toShare: [], read: read)
```

Daily totals: `HKStatisticsCollectionQuery` with `.cumulativeSum` and a one-day interval
(anchor at local midnight). Sleep: `HKSampleQuery` on `HKCategoryType(.sleepAnalysis)`,
then `HKCategoryValueSleepAnalysis(rawValue: sample.value)` over `.asleepDeep`,
`.asleepCore`, `.asleepREM`, `.awake`, `.inBed`; sum `endDate - startDate` per stage.
Sleep stages are recorded by watchOS itself from motion and heart rate overnight; a
third-party app reads them in the morning, it does not sample overnight.

A simulator has no Health samples: an empty result there is the expected outcome and is
not evidence the query works. Seed fixture data behind a launch argument for UI tests,
and say in the report that real data was not seen unless it was run on a device.
Widgets cannot prompt for authorization and have no background `HKHealthStore` access:
the app computes and writes to the App Group, the widget reads that.
