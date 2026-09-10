# Title detail crash mitigation

Observed physical Apple TV crash: EXC_BAD_ACCESS in swift_getTypeByMangledNameImpl, reached from ContentDetailView.secondaryActionsRail while building the hero. The snapshot import had already succeeded.

The action factory now returns a concrete ContentDetailActionButton rather than exposing its full modified-button type through an opaque return. All existing actions remain present. This targets metadata expansion; the screenshot alone does not prove the underlying Swift runtime cause.

AddonDiskPersistence also recreates its parent immediately before atomic writes. A native fixture exercised first write with missing ancestors and a second write after removing the directory; both passed.

Final signed generic tvOS and iOS builds passed. No simulators used. Physical repeat of the originally crashing detail navigation remains required; build success is not runtime verification. No Worker or backup schema changes.
