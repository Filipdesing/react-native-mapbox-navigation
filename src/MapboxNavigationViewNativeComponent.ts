import type { HostComponent, ViewProps } from 'react-native';

import type { Double } from 'react-native/Libraries/Types/CodegenTypes';
import type { NativeEventsProps } from './types';
import codegenNativeComponent from 'react-native/Libraries/Utilities/codegenNativeComponent';

type NativeCoordinate = number[];
interface NativeProps extends ViewProps {
  mute?: boolean;
  separateLegs?: boolean;
  distanceUnit?: string;
  startOrigin: NativeCoordinate;
  waypoints?: {
    latitude: Double;
    longitude: Double;
    name?: string;
    separatesLegs?: boolean;
  }[];
  destinationTitle?: string;
  destination: NativeCoordinate;
  language?: string;
  showCancelButton?: boolean;
  shouldSimulateRoute?: boolean;
  showsEndOfRouteFeedback?: boolean;
  hideStatusView?: boolean;
  travelMode?: string;
  /**
   * JSON string of a Mapbox Directions API v5 response. When provided, the SDK
   * skips its own Directions request and navigates the supplied route. Required
   * for truck routing — feed a HERE-computed route converted to Mapbox format.
   * The SDK's internal rerouter is disabled when this prop is set; the app must
   * compute reroutes itself and call back with an updated customRoute.
   */
  customRoute?: string;
}

export default codegenNativeComponent<NativeProps>(
  'MapboxNavigationView'
) as HostComponent<NativeProps & NativeEventsProps>;
