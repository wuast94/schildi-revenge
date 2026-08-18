package chat.schildi.revenge

import chat.schildi.revenge.util.OperatingSystem
import chat.schildi.revenge.util.SystemInfo
import co.touchlab.kermit.Logger
import java.awt.Desktop

internal object MacOpenUriHandler {
    private val log = Logger.withTag("MacOpenUriHandler")
    private val dispatcher = MacOpenUriDispatcher(::deeplinkCommandOrNull)

    fun install() {
        check(SystemInfo.getOs() == OperatingSystem.Mac) {
            "The macOS URI handler must only be installed on macOS"
        }

        runCatching {
            check(Desktop.isDesktopSupported()) { "java.awt.Desktop is not supported" }
            val desktop = Desktop.getDesktop()
            check(desktop.isSupported(Desktop.Action.APP_OPEN_URI)) {
                "java.awt.Desktop APP_OPEN_URI is not supported"
            }
            desktop.setOpenURIHandler { event -> dispatcher.dispatch(event.uri.toString()) }
        }.onFailure { error ->
            log.e("Failed to install macOS URI handler", error)
        }
    }

    fun startConsuming(consumer: (String) -> Unit) {
        check(SystemInfo.getOs() == OperatingSystem.Mac) {
            "The macOS URI handler must only be consumed on macOS"
        }
        dispatcher.startConsuming(consumer)
    }
}

internal class MacOpenUriDispatcher(
    private val commandForUri: (String) -> String?,
) {
    private val lock = Any()
    private val pendingCommands = ArrayDeque<String>()
    private var consumer: ((String) -> Unit)? = null
    private var isDraining = false

    fun dispatch(uri: String) {
        val command = commandForUri(uri) ?: return
        val shouldDrain = synchronized(lock) {
            pendingCommands.addLast(command)
            beginDrainingIfPossible()
        }
        if (shouldDrain) drainPendingCommands()
    }

    fun startConsuming(consumer: (String) -> Unit) {
        val shouldDrain = synchronized(lock) {
            this.consumer = consumer
            beginDrainingIfPossible()
        }
        if (shouldDrain) drainPendingCommands()
    }

    private fun beginDrainingIfPossible(): Boolean {
        if (consumer == null || isDraining || pendingCommands.isEmpty()) return false
        isDraining = true
        return true
    }

    private fun drainPendingCommands() {
        while (true) {
            val next = synchronized(lock) {
                val currentConsumer = consumer
                val command = pendingCommands.removeFirstOrNull()
                if (currentConsumer == null || command == null) {
                    isDraining = false
                    null
                } else {
                    currentConsumer to command
                }
            } ?: return

            try {
                next.first(next.second)
            } catch (error: Throwable) {
                synchronized(lock) { isDraining = false }
                throw error
            }
        }
    }
}
