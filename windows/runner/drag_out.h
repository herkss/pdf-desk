#ifndef RUNNER_DRAG_OUT_H_
#define RUNNER_DRAG_OUT_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Registers the "pdf_desk/drag_out" channel. Its "startFileDrag" method
// takes a list of file paths and starts a Windows (OLE) drag of those
// files, so they can be dropped on the desktop or into an Explorer window
// like files dragged out of Explorer. Returns the drop effect
// (0 none, 1 copy, 2 move).
//
// |view| is the Flutter view's window: after the drag the Windows drag
// loop has swallowed the mouse-button release, so one is posted to the
// view to end the drag on the Flutter side too.
void RegisterDragOutChannel(flutter::BinaryMessenger* messenger, HWND view);

#endif  // RUNNER_DRAG_OUT_H_
