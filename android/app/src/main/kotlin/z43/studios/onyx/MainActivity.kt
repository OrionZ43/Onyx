package z43.studios.onyx

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "z43.studios.onyx/native"
    private val NOTIFICATION_EVENTS_CHANNEL = "z43.studios.onyx/notification_events"

    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibraryDir" -> {
                        result.success(applicationInfo.nativeLibraryDir)
                    }

                    // Показать/обновить persistent-уведомление со статусом VPN.
                    // Аргументы: nodeName (String), rxBytes (Long), txBytes (Long),
                    // connected (Boolean).
                    "showVpnNotification" -> {
                        val args = call.arguments as? Map<*, *>
                        val nodeName = args?.get("nodeName") as? String ?: "Onyx VPN"
                        val rxBytes = (args?.get("rxBytes") as? Number)?.toLong() ?: 0L
                        val txBytes = (args?.get("txBytes") as? Number)?.toLong() ?: 0L
                        val connected = args?.get("connected") as? Boolean ?: false
                        OnyxNotificationManager.show(
                            applicationContext,
                            nodeName,
                            rxBytes,
                            txBytes,
                            connected,
                        )
                        result.success(null)
                    }

                    // Убрать уведомление (VPN отключён).
                    "cancelVpnNotification" -> {
                        OnyxNotificationManager.cancel(applicationContext)
                        result.success(null)
                    }

                    // Список установленных приложений для split tunneling.
                    // Возвращает List<Map>: packageName, appName, isSystem.
                    // Иконки намеренно не передаются — сериализация сотен
                    // PNG через MethodChannel заметно тормозит открытие
                    // экрана, а глass-аватар с первой буквой выглядит
                    // консистентнее с дизайн-системой.
                    "getInstalledApps" -> {
                        Thread {
                            try {
                                val pm = packageManager
                                val apps = pm.getInstalledApplications(0)
                                    .filter { it.packageName != packageName }
                                    .map {
                                        mapOf(
                                            "packageName" to it.packageName,
                                            "appName" to pm
                                                .getApplicationLabel(it)
                                                .toString(),
                                            "isSystem" to ((it.flags and
                                                android.content.pm.ApplicationInfo
                                                    .FLAG_SYSTEM) != 0),
                                        )
                                    }
                                    .sortedBy {
                                        (it["appName"] as String).lowercase()
                                    }
                                runOnUiThread { result.success(apps) }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("APPS_ERROR", e.message, null)
                                }
                            }
                        }.start()
                    }

                    // Открывает системные настройки VPN — там пользователь
                    // включает Always-on VPN и "Блокировать соединения без
                    // VPN" (системный Kill Switch, надёжнее любого
                    // программного).
                    "openVpnSettings" -> {
                        try {
                            startActivity(
                                android.content.Intent(
                                    android.provider.Settings.ACTION_VPN_SETTINGS
                                )
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SETTINGS_ERROR", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        // Отдельный EventChannel: Dart подписывается один раз на старте,
        // и получает событие "disconnect_requested" каждый раз когда
        // пользователь жмёт кнопку "ОТКЛЮЧИТЬ" в уведомлении из шторки.
        // Это разрывает зависимость от того, открыто ли приложение —
        // BroadcastReceiver в OnyxNotificationManager ловит нажатие даже
        // если Activity на паузе, и мы прокидываем событие в Dart-слой
        // как только движок снова активен.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_EVENTS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                    OnyxNotificationManager.registerDisconnectReceiver(applicationContext) {
                        runOnUiThread {
                            eventSink?.success("disconnect_requested")
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    OnyxNotificationManager.unregisterDisconnectReceiver(applicationContext)
                    eventSink = null
                }
            })
    }

    override fun onDestroy() {
        OnyxNotificationManager.unregisterDisconnectReceiver(applicationContext)
        super.onDestroy()
    }
}