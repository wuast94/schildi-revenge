package chat.schildi.revenge

import kotlin.test.Test
import kotlin.test.assertEquals

class MacOpenUriDispatcherTest {
    @Test
    fun `queues supported links until the application is ready`() {
        val consumed = mutableListOf<String>()
        val dispatcher = MacOpenUriDispatcher(::deeplinkCommandOrNull)

        dispatcher.dispatch("matrix:r/revenge:schildi.chat")
        dispatcher.dispatch("https://schildi.chat")
        dispatcher.dispatch("schildichat://room/%23revenge%3Aschildi.chat")

        assertEquals(emptyList(), consumed)

        dispatcher.startConsuming(consumed::add)

        assertEquals(
            listOf(
                "ConsumeLink matrix:r/revenge:schildi.chat",
                "ConsumeLink schildichat://room/%23revenge%3Aschildi.chat",
            ),
            consumed,
        )
    }

    @Test
    fun `forwards supported links immediately after the application is ready`() {
        val consumed = mutableListOf<String>()
        val dispatcher = MacOpenUriDispatcher(::deeplinkCommandOrNull)
        dispatcher.startConsuming(consumed::add)

        dispatcher.dispatch("matrix:u/alice:example.org")

        assertEquals(listOf("ConsumeLink matrix:u/alice:example.org"), consumed)
    }

    @Test
    fun `preserves order when another link arrives while queued links are draining`() {
        val consumed = mutableListOf<String>()
        val dispatcher = MacOpenUriDispatcher(::deeplinkCommandOrNull)
        dispatcher.dispatch("matrix:u/alice:example.org")
        dispatcher.dispatch("matrix:u/bob:example.org")

        dispatcher.startConsuming { command ->
            consumed.add(command)
            if (consumed.size == 1) {
                dispatcher.dispatch("matrix:u/carol:example.org")
            }
        }

        assertEquals(
            listOf(
                "ConsumeLink matrix:u/alice:example.org",
                "ConsumeLink matrix:u/bob:example.org",
                "ConsumeLink matrix:u/carol:example.org",
            ),
            consumed,
        )
    }
}
