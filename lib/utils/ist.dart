/// India Standard Time helpers.
///
/// Payment times are always shown and entered in IST, whatever timezone the
/// device is set to, and always stored as UTC. IST has no daylight saving,
/// so a fixed offset is exact.
library;

const Duration kIstOffset = Duration(hours: 5, minutes: 30);

/// IST wall-clock for [instant], as a naive DateTime: only its y/m/d h:m
/// fields are meaningful — never send this to the server directly.
DateTime toIstWall(DateTime instant) => instant.toUtc().add(kIstOffset);

/// The UTC instant for an IST wall-clock DateTime.
DateTime istWallToUtc(DateTime wall) => DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
    ).subtract(kIstOffset);

/// The current time as an IST wall clock.
DateTime istNow() => toIstWall(DateTime.now());
