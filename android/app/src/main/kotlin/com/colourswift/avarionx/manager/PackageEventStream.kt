package com.colourswift.avarionx.manager

import io.flutter.plugin.common.EventChannel

object PackageEventStream {
    private var sink: EventChannel.EventSink? = null

    fun attach(s: EventChannel.EventSink) {
        sink = s
    }

    fun detach() {
        sink = null
    }

    fun emit(data: Map<String, Any?>) {
        sink?.success(data)
    }
}
