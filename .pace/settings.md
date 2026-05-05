# Settings
_Persistent configuration for the PACE workflow. This file is not cleared by /pace:complete._

## Model

<!-- Valid values: sonnet, opus, haiku                                    -->
<!-- These match the short model names accepted by the Claude Code Agent  -->
<!-- tool's `model` parameter.                                            -->

<!-- plan-model: Model for planning-phase agents — domain planners,       -->
<!-- synthesiser, research agents, codebase analyst. These agents make     -->
<!-- architectural decisions and benefit from stronger reasoning.          -->

<!-- execute-model: Model for execution-phase agents — specialist          -->
<!-- implementers, verification, fixes, documentation patches. These      -->
<!-- agents do bounded, well-specified work.                               -->

<!-- When unset (empty), agents inherit the session model — behaviour is   -->
<!-- identical to before this setting existed.                             -->

plan-model: opus
execute-model: sonnet
