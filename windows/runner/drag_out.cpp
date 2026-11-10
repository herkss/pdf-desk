#include "drag_out.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <ole2.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <memory>
#include <string>
#include <vector>

namespace {

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                              nullptr, 0);
  std::wstring out(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()),
                      out.data(), n);
  return out;
}

// The shell's own data object for |paths|: it offers every format Explorer
// and the desktop accept (CF_HDROP, shell ID lists, ...). Returns nullptr if
// a path can't be resolved.
IDataObject* DataObjectForFiles(const std::vector<std::wstring>& paths) {
  std::vector<PCIDLIST_ABSOLUTE> pidls;
  for (const auto& path : paths) {
    PIDLIST_ABSOLUTE pidl = nullptr;
    if (FAILED(SHParseDisplayName(path.c_str(), nullptr, &pidl, 0, nullptr)) ||
        pidl == nullptr) {
      continue;
    }
    pidls.push_back(pidl);
  }
  IDataObject* data = nullptr;
  if (!pidls.empty()) {
    IShellItemArray* items = nullptr;
    if (SUCCEEDED(SHCreateShellItemArrayFromIDLists(
            static_cast<UINT>(pidls.size()), pidls.data(), &items))) {
      items->BindToHandler(nullptr, BHID_DataObject, IID_PPV_ARGS(&data));
      items->Release();
    }
  }
  for (auto pidl : pidls) {
    CoTaskMemFree(const_cast<void*>(static_cast<const void*>(pidl)));
  }
  return data;
}

}  // namespace

void RegisterDragOutChannel(flutter::BinaryMessenger* messenger, HWND view) {
  // OLE drag and drop needs OLE, not just COM, on this thread.
  OleInitialize(nullptr);
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      channel;
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "pdf_desk/drag_out",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [view](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "startFileDrag") {
          result->NotImplemented();
          return;
        }
        const auto* list =
            std::get_if<flutter::EncodableList>(call.arguments());
        std::vector<std::wstring> paths;
        if (list != nullptr) {
          for (const auto& v : *list) {
            if (const auto* s = std::get_if<std::string>(&v)) {
              paths.push_back(Utf8ToWide(*s));
            }
          }
        }
        // Preparing the files can take a moment; if the button was let go
        // meanwhile, a drag now would drop wherever the mouse happens to be.
        const int button =
            GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
        if ((GetAsyncKeyState(button) & 0x8000) == 0) {
          result->Success(flutter::EncodableValue(0));
          return;
        }
        IDataObject* data = paths.empty() ? nullptr : DataObjectForFiles(paths);
        if (data == nullptr) {
          result->Success(flutter::EncodableValue(0));
          return;
        }
        // Copy only: the desk keeps its documents, and what lands in the
        // folder is a document with the same name.
        DWORD effect = DROPEFFECT_NONE;
        HRESULT hr = SHDoDragDrop(view, data, nullptr, DROPEFFECT_COPY, &effect);
        data->Release();

        // The drag loop ate the button release; tell the Flutter view so
        // its own drag ends instead of following the mouse.
        POINT pt;
        GetCursorPos(&pt);
        ScreenToClient(view, &pt);
        PostMessage(view, WM_LBUTTONUP, 0, MAKELPARAM(pt.x, pt.y));

        int code = 0;
        if (hr == DRAGDROP_S_DROP) {
          code = (effect & DROPEFFECT_MOVE) ? 2 : (effect & DROPEFFECT_COPY) ? 1 : 0;
        }
        result->Success(flutter::EncodableValue(code));
      });
}
