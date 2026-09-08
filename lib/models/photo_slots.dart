/// Photo checklist mirroring the AVO page. `field` must match the
/// VehiclePhotosDto property name on the backend exactly.
class PhotoSlot {
  final String field;
  final String label;
  final bool mandatory;
  final bool useFrontCamera;

  const PhotoSlot(this.field, this.label,
      {this.mandatory = false, this.useFrontCamera = false});
}

const List<PhotoSlot> kPhotoSlots = [
  PhotoSlot('FrontLeftSide', 'Front Left Side', mandatory: true),
  PhotoSlot('FrontRightSide', 'Front Right Side', mandatory: true),
  PhotoSlot('RearLeftSide', 'Rear Left Side', mandatory: true),
  PhotoSlot('RearRightSide', 'Rear Right Side', mandatory: true),
  PhotoSlot('FrontViewGrille', 'Front View (Grille)', mandatory: true),
  PhotoSlot('RearViewTailgate', 'Rear View (Tailgate)', mandatory: true),
  PhotoSlot('DriverSideProfile', "Driver's Side Profile", mandatory: true),
  PhotoSlot('PassengerSideProfile', 'Passenger Side Profile', mandatory: true),
  PhotoSlot('Dashboard', 'Dashboard'),
  PhotoSlot('InstrumentCluster', 'Instrument Cluster'),
  PhotoSlot('EngineBay', 'Engine Bay', mandatory: true),
  PhotoSlot('VinPlate', 'VIN Plate', mandatory: true),
  PhotoSlot('ChassisImprint', 'Chassis Imprint', mandatory: true),
  PhotoSlot('GearInterior', 'Gear (Interior)'),
  PhotoSlot('FrontSeat', 'Front Seat'),
  PhotoSlot('RearSeat', 'Rear Seat'),
  PhotoSlot('DashboardCloseup', 'Dashboard Close-up'),
  PhotoSlot('Odometer', 'Odometer', mandatory: true),
  PhotoSlot('SelfieWithVehicle', 'Selfie with Vehicle',
      mandatory: true, useFrontCamera: true),
  PhotoSlot('Underbody', 'Under Body'),
  PhotoSlot('TireFrontLeft', 'Tire Front Left'),
  PhotoSlot('TireFrontRight', 'Tire Front Right'),
  PhotoSlot('TireRearLeft', 'Tire Rear Left'),
  PhotoSlot('TireRearRight', 'Tire Rear Right'),
  PhotoSlot('ChassisVerification', 'Chassis Verification', mandatory: true),
  PhotoSlot('ChassisStencilTrace', 'Chassis Stencil Trace', mandatory: true),
  PhotoSlot('WorkingOperationPhoto', 'Working / Operation Photo',
      mandatory: true),
];
