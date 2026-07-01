package z43.studios.onyx

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.app.NotificationCompat

/**
 * Управляет persistent-уведомлением "VPN подключён" с живой статистикой
 * трафика и кнопкой "Отключить".
 *
 * Почему свой код, а не только то что даёт flutter_v2ray "из коробки":
 * плагин создаёт своё уведомление на уровне нативного VpnService, но не
 * даёт кастомизировать текст/цвета под наш дизайн, и его кнопка
 * disconnect не проходит через наш VpnController (не обновляет Riverpod
 * state в Dart). Здесь мы держим ОТДЕЛЬНОЕ собственное уведомление
 * (второй notification ID), которое полностью под нашим контролем —
 * кнопка шлёт broadcast → MainActivity ловит его → зовёт Dart через
 * EventChannel → VpnController.disconnect() отрабатывает как обычно.
 */
object OnyxNotificationManager {
    const val CHANNEL_ID = "onyx_vpn_status"
    const val NOTIFICATION_ID = 4301
    const val ACTION_DISCONNECT = "z43.studios.onyx.ACTION_DISCONNECT"

    private var receiver: BroadcastReceiver? = null

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Статус Onyx VPN",
                    NotificationManager.IMPORTANCE_LOW, // без звука — это статус-уведомление
                ).apply {
                    description = "Показывает статус подключения и скорость VPN"
                    setShowBadge(false)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    /**
     * Регистрирует receiver на нажатие кнопки "Отключить" в уведомлении.
     * [onDisconnectRequested] дергается на UI/main thread.
     */
    fun registerDisconnectReceiver(context: Context, onDisconnectRequested: () -> Unit) {
        unregisterDisconnectReceiver(context)
        val r = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                if (intent?.action == ACTION_DISCONNECT) {
                    onDisconnectRequested()
                }
            }
        }
        receiver = r
        val filter = IntentFilter(ACTION_DISCONNECT)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(r, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(r, filter)
        }
    }

    fun unregisterDisconnectReceiver(context: Context) {
        receiver?.let {
            try {
                context.unregisterReceiver(it)
            } catch (_: IllegalArgumentException) {
                // уже не зарегистрирован — не критично
            }
        }
        receiver = null
    }

    /**
     * Показывает/обновляет уведомление.
     * [nodeName] — имя сервера, [rxBytes]/[txBytes] — суммарный трафик за сессию
     * в байтах (как приходит из statsStream в Dart), [connected] — статус.
     */
    fun show(
        context: Context,
        nodeName: String,
        rxBytes: Long,
        txBytes: Long,
        connected: Boolean,
    ) {
        ensureChannel(context)

        val disconnectIntent = Intent(ACTION_DISCONNECT).apply {
            setPackage(context.packageName)
        }
        val disconnectPendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            disconnectIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val openAppPendingIntent = PendingIntent.getActivity(
            context,
            0,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val title = if (connected) "Onyx VPN — подключено" else "Onyx VPN — подключение..."
        val subtitle = if (connected) {
            "$nodeName · ↓${_fmt(rxBytes)} ↑${_fmt(txBytes)}"
        } else {
            nodeName
        }

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText(subtitle)
            .setOngoing(true) // нельзя смахнуть — так и должно быть для активного VPN
            .setOnlyAlertOnce(true) // не дёргает звук/вибро на каждое обновление скорости
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(openAppPendingIntent)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)

        if (connected) {
            builder.addAction(
                0,
                "ОТКЛЮЧИТЬ",
                disconnectPendingIntent,
            )
        }

        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, builder.build())
    }

    fun cancel(context: Context) {
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(NOTIFICATION_ID)
    }

    private fun _fmt(bytes: Long): String {
        if (bytes < 1024) return "${bytes}Б"
        if (bytes < 1024 * 1024) return "${bytes / 1024}КБ"
        return "${"%.1f".format(bytes / (1024.0 * 1024.0))}МБ"
    }
}