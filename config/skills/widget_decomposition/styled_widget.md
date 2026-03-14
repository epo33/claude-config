# styled_widget : référence des notations postfix

Package `styled_widget` v0.4.1 —
sources : `C:\Users\emman\AppData\Local\Pub\Cache\hosted\pub.dev\styled_widget-0.4.1\lib\src\extensions\`

## Sur `Widget` (48 méthodes)

| Postfix | Widget remplacé |
|---------|----------------|
| `.padding(...)` | `Padding` |
| `.paddingDirectional(...)` | `Padding` (directionnel) |
| `.expanded({flex})` | `Expanded` |
| `.flexible({flex, fit})` | `Flexible` |
| `.width(w)` / `.height(h)` | `SizedBox` |
| `.constrained({width, height, min/max...})` | `ConstrainedBox` |
| `.alignment(a)` | `Align` |
| `.center({widthFactor, heightFactor})` | `Center` |
| `.opacity(v)` | `Opacity` |
| `.offstage({offstage})` | `Offstage` |
| `.backgroundColor(color)` | `ColoredBox` / `DecoratedBox` |
| `.backgroundImage(image)` | `DecoratedBox` |
| `.backgroundGradient(gradient)` | `DecoratedBox` |
| `.backgroundLinearGradient(...)` | `DecoratedBox` |
| `.backgroundRadialGradient(...)` | `DecoratedBox` |
| `.backgroundSweepGradient(...)` | `DecoratedBox` |
| `.backgroundBlendMode(mode)` | `DecoratedBox` |
| `.backgroundBlur(sigma)` | `BackdropFilter` |
| `.borderRadius({all, topLeft...})` | `DecoratedBox` |
| `.borderRadiusDirectional(...)` | `DecoratedBox` |
| `.clipRRect({all, topLeft...})` | `ClipRRect` |
| `.clipRect({clipper, behavior})` | `ClipRect` |
| `.clipOval()` | `ClipOval` |
| `.border({all, left, right, top, bottom, color, style})` | `DecoratedBox` |
| `.decorated({color, border, borderRadius, boxShadow...})` | `DecoratedBox` |
| `.elevation(e, {borderRadius, shadowColor})` | `Material` (élévation) |
| `.neumorphism({elevation, borderRadius...})` | style neumorphique |
| `.boxShadow({color, offset, blurRadius, spreadRadius})` | `DecoratedBox` |
| `.rotate({angle, origin, alignment})` | `Transform.rotate` |
| `.scale({all, x, y, origin})` | `Transform.scale` |
| `.translate({offset})` | `Transform.translate` |
| `.transform({transform, origin, alignment})` | `Transform` |
| `.overflow({alignment, min/maxWidth/Height})` | `OverflowBox` |
| `.scrollable({scrollDirection, physics...})` | `SingleChildScrollView` |
| `.positioned({left, top, right, bottom, width, height})` | `Positioned` |
| `.positionedDirectional({start, end, top, bottom...})` | `PositionedDirectional` |
| `.safeArea({top, bottom, left, right})` | `SafeArea` |
| `.ripple({focusColor, splashColor...})` | `InkWell` |
| `.gestures({onTap, onLongPress...})` | `GestureDetector` |
| `.aspectRatio({aspectRatio})` | `AspectRatio` |
| `.fittedBox({fit, alignment})` | `FittedBox` |
| `.fractionallySizedBox({widthFactor, heightFactor})` | `FractionallySizedBox` |
| `.card({color, elevation, shape...})` | `Card` |
| `.limitedBox({maxWidth, maxHeight})` | `LimitedBox` |
| `.semanticsLabel(label)` | `Semantics` |
| `.animate(duration, curve)` | animation implicite |
| `.parent(builder)` | wrapper générique |

## Sur `Text` (17 méthodes)

| Postfix | Équivalent |
|---------|-----------|
| `.bold()` | `fontWeight: FontWeight.bold` |
| `.italic()` | `fontStyle: FontStyle.italic` |
| `.fontWeight(w)` | `style: TextStyle(fontWeight: w)` |
| `.fontSize(s)` | `style: TextStyle(fontSize: s)` |
| `.fontFamily(f)` | `style: TextStyle(fontFamily: f)` |
| `.letterSpacing(s)` | `style: TextStyle(letterSpacing: s)` |
| `.wordSpacing(s)` | `style: TextStyle(wordSpacing: s)` |
| `.textColor(c)` | `style: TextStyle(color: c)` |
| `.textAlignment(a)` | `textAlign: a` |
| `.textDirection(d)` | `textDirection: d` |
| `.textBaseline(b)` | `style: TextStyle(textBaseline: b)` |
| `.textWidthBasis(b)` | `textWidthBasis: b` |
| `.textStyle(s)` | `style: s` |
| `.textScale(f)` | `textScaleFactor: f` |
| `.textShadow({color, blurRadius, offset})` | `style: TextStyle(shadows: ...)` |
| `.textElevation(e, {angle, color, opacityRatio})` | élévation simulée |
| `.copyWith(...)` | copie paramétrique |

## Sur `TextSpan` (13 méthodes)

Mêmes méthodes que `Text` sauf `textAlignment`, `textDirection`, `textWidthBasis`, `textScale` :
`.bold()`, `.italic()`, `.fontWeight()`, `.fontSize()`, `.fontFamily()`,
`.letterSpacing()`, `.wordSpacing()`, `.textColor()`, `.textBaseline()`,
`.textStyle()`, `.textShadow()`, `.textElevation()`, `.copyWith()`.

## Sur `List<Widget>`

| Postfix | Widget créé |
|---------|------------|
| `.toColumn({...})` | `Column` |
| `.toRow({...})` | `Row` |
| `.toStack({...})` | `Stack` |
| `.toWrap({...})` | `Wrap` |

## Sur `Icon`

| Postfix | Équivalent |
|---------|-----------|
| `.iconSize(s)` | `size: s` |
| `.iconColor(c)` | `color: c` |
