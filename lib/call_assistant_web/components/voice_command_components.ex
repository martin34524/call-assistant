defmodule CallAssistantWeb.VoiceCommandComponents do
  @moduledoc """
  The "please call Jane" voice-command mic panel, shared between
  `CallAssistantWeb.LeadsLive` and `CallAssistantWeb.Admin.CallsLive` - one
  function component so the colocated JS hook (Web Speech API) is only
  ever compiled once. See `Phoenix.LiveView.ColocatedHook` - both the
  `phx-hook=".VoiceCommand"` element and its `<script>` live in this one
  component's own template, so the dot-name resolves the same way
  regardless of which page renders it.

  Server-side event contract (implemented identically in both LiveViews):
  client -> server `"voice_start"`, `"voice_transcript"` (`%{"text" =>
  ...}`, meaning depends on the current `:voice_step`), `"voice_recognition_error"`,
  `"voice_pick_candidate"`, `"voice_cancel"`, `"voice_confirm"`. Server ->
  client `push_event/3`: `"voice_listen"` (`%{prompt: ...}` - hook speaks it
  then restarts recognition) and `"voice_stop"`.
  """

  use CallAssistantWeb, :html

  attr :voice_step, :atom, required: true
  attr :voice_name, :string, default: nil
  attr :voice_phone, :string, default: nil
  attr :voice_context, :string, default: nil
  attr :voice_candidates, :list, default: []
  attr :voice_error, :string, default: nil

  def panel(assigns) do
    ~H"""
    <div
      id="voice-command"
      phx-hook=".VoiceCommand"
      data-step={@voice_step}
      class="mb-6 rounded-xl border border-base-300 bg-base-100 p-4"
    >
      <div :if={@voice_step == :idle} class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2 text-sm text-base-content/60">
          <.icon name="hero-microphone-micro" class="size-4" />
          Place a call by voice - try "Call Jane."
        </div>
        <button type="button" phx-click="voice_start" class="btn btn-sm btn-outline" data-voice-mic>
          <.icon name="hero-microphone-micro" class="size-4" /> Voice command
        </button>
      </div>

      <div :if={@voice_step == :awaiting_command} class="flex items-center gap-2 text-sm">
        <span class="loading loading-dots loading-sm text-primary"></span>
        Listening… say "call" and a name.
        <button
          type="button"
          phx-click="voice_cancel"
          class="ml-auto text-xs text-base-content/50 hover:text-base-content"
        >
          Cancel
        </button>
      </div>

      <div :if={@voice_step == :awaiting_phone} class="text-sm">
        <p class="mb-2 text-base-content/70">
          I don't have a number on file for <strong>{@voice_name}</strong>
          . What's their phone number?
        </p>
        <button
          type="button"
          phx-click="voice_cancel"
          class="text-xs text-base-content/50 hover:text-base-content"
        >
          Cancel
        </button>
      </div>

      <div :if={@voice_step == :disambiguating} class="text-sm">
        <p class="mb-2 text-base-content/70">
          I found more than one number for <strong>{@voice_name}</strong> - which one?
        </p>
        <div class="flex flex-wrap gap-2">
          <button
            :for={{contact, index} <- Enum.with_index(@voice_candidates)}
            type="button"
            phx-click="voice_pick_candidate"
            phx-value-index={index}
            class="btn btn-sm btn-outline"
          >
            {contact.phone}
          </button>
        </div>
        <button
          type="button"
          phx-click="voice_cancel"
          class="mt-2 text-xs text-base-content/50 hover:text-base-content"
        >
          Cancel
        </button>
      </div>

      <div :if={@voice_step == :awaiting_context} class="flex items-center gap-2 text-sm">
        <span class="loading loading-dots loading-sm text-primary"></span>
        Listening… what's the call about?
        <button
          type="button"
          phx-click="voice_cancel"
          class="ml-auto text-xs text-base-content/50 hover:text-base-content"
        >
          Cancel
        </button>
      </div>

      <div :if={@voice_step == :confirming} class="text-sm">
        <p class="mb-3 text-base-content/70">
          Call <strong>{@voice_name}</strong> at <strong>{@voice_phone}</strong>
          <span :if={@voice_context}>about: "{@voice_context}"</span>?
        </p>
        <div class="flex gap-2">
          <button type="button" phx-click="voice_cancel" class="btn btn-sm btn-ghost">
            Cancel
          </button>
          <button type="button" phx-click="voice_confirm" class="btn btn-sm btn-primary">
            <.icon name="hero-phone-arrow-up-right-micro" class="size-4" /> Confirm & call
          </button>
        </div>
      </div>

      <div :if={@voice_error} class="mt-2 flex items-center gap-1.5 text-sm text-error">
        <.icon name="hero-exclamation-triangle-micro" class="size-4" /> {@voice_error}
      </div>

      <p data-voice-unsupported hidden class="mt-2 text-sm text-warning">
        Voice input isn't supported in this browser - try Chrome or Edge.
      </p>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".VoiceCommand">
        export default {
          mounted() {
            const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
            this.supported = !!SpeechRecognition

            if (!this.supported) {
              this.el.querySelector("[data-voice-unsupported]")?.removeAttribute("hidden")
              return
            }

            this.recognition = new SpeechRecognition()
            this.recognition.continuous = false
            this.recognition.interimResults = true
            this.recognition.lang = "en-US"

            this.recognition.onresult = (event) => {
              let finalText = ""
              for (let i = event.resultIndex; i < event.results.length; i++) {
                if (event.results[i].isFinal) {
                  finalText += event.results[i][0].transcript
                }
              }
              if (finalText.trim()) {
                this.pushEvent("voice_transcript", {text: finalText.trim()})
              }
            }

            this.recognition.onerror = (event) => {
              if (event.error === "no-speech" || event.error === "aborted") return
              this.pushEvent("voice_recognition_error", {reason: event.error})
            }

            this.handleEvent("voice_listen", ({prompt}) => {
              const startListening = () => {
                try { this.recognition.start() } catch (e) { /* already listening */ }
              }
              if (prompt && window.speechSynthesis) {
                window.speechSynthesis.cancel()
                const utterance = new SpeechSynthesisUtterance(prompt)
                utterance.onend = startListening
                utterance.onerror = startListening
                window.speechSynthesis.speak(utterance)
              } else {
                startListening()
              }
            })

            this.handleEvent("voice_stop", () => {
              try { this.recognition.stop() } catch (e) { /* not listening */ }
              window.speechSynthesis?.cancel()
            })
          },
          destroyed() {
            if (this.recognition) { try { this.recognition.stop() } catch (e) {} }
            window.speechSynthesis?.cancel()
          }
        }
      </script>
    </div>
    """
  end
end
