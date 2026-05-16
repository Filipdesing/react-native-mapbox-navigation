package com.mapboxnavigation

import android.view.View
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.uimanager.SimpleViewManager
import org.intellij.lang.annotations.Language

abstract class MapboxNavigationViewManagerSpec<T : View> : SimpleViewManager<T>() {
  abstract fun setStartOrigin(view: T?, value: ReadableArray?)
  abstract fun setDestination(view: T?, value: ReadableArray?)
  abstract fun setDestinationTitle(view: T?, value: String?)
  abstract fun setWaypoints(view: T?, value: ReadableArray?)
  abstract fun setDistanceUnit(view: T?, value: String?)
  abstract fun setLanguage(view: T?, value: String?)
  abstract fun setMute(view: T?, value: Boolean)
  abstract fun setShowCancelButton(view: T?, value: Boolean)
  abstract fun setTravelMode(view: T?, value: String?)
  abstract fun setCustomRoute(view: T?, value: String?)
  abstract fun setSeparateLegs(view: T?, value: Boolean)
  abstract fun setShouldSimulateRoute(view: T?, value: Boolean)
  abstract fun setShowsEndOfRouteFeedback(view: T?, value: Boolean)
  abstract fun setHideStatusView(view: T?, value: Boolean)
}
