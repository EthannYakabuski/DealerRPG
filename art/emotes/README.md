# NPC reactions

Eight unmodified icons from **Kenney Emotes**, `Assets/UI_emotes/PNG/Vector/Style 1`.
The supplied pack is CC0; its original license is included beside these images.

The pack contains 30 expressions in eight vector styles and eight pixel styles
(480 individual PNGs), 16 spritesheets with XML atlases, 16 tilesheets, a preview,
and the SVG/SWF vector source. Styles 1–7 add different speech/thought balloons;
style 8 has transparent icons without a balloon. The bright, white Style 1 speech
bubble remains legible above the existing small 3D characters against both grass
and nighttime streets. Only this consistent style is included in the game export.

`scripts/npc_emote.gd` maps happy, angry, sad, alert, question, wave, music and cash
to these images. The ellipsis bubble represents a friendly greeting (`wave`).
Bubbles are cosmetic reactions, never a detector for hidden informants. They are
billboarded, depth-tested, replaced on repeated reactions, and expire after a
short animation. They do not add persistent actors, physics bodies or audio.
