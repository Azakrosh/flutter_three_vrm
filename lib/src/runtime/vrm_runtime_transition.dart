import '../models/vrm_exception.dart';

const VrmRuntimeException vrmRuntimeTransitionCancellation =
    VrmRuntimeException(
      code: 'canceled',
      message: 'The pending command was canceled by a runtime transition.',
    );

bool isExpectedVrmRuntimeCancellation(Object error) =>
    error is VrmRuntimeException && error.code == 'canceled';
