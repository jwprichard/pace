# Settings
_Persistent configuration for the PACE workflow. This file is not cleared by /pace:complete._

## Model

<!-- Valid values: sonnet, opus, haiku                                    -->
<!-- These match the short model names accepted by the Claude Code Agent  -->
<!-- tool's `model` parameter.                                            -->
<!--                                                                      -->
<!-- When set, every specialist agent spawned by PACE commands will use    -->
<!-- this model. The orchestrator's own model is never affected -- it      -->
<!-- always runs on whatever model the session was started with.           -->
<!--                                                                      -->
<!-- When unset (empty or commented out), agents inherit the session       -->
<!-- model -- behaviour is identical to before this setting existed.       -->

model:
