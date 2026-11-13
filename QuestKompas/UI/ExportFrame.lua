-- QuestKompas: export and import windows for learned data (spec 4.6).
local _, ns = ...

local EF = {}
ns.ExportFrame = EF
local L = ns.L

local exportWin, importWin

function EF:ShowExport(scope)
  local str, err, n = ns.Learn:Export(scope)
  if not str then
    ns:Print(string.format(L["EXPORT_FAILED"], tostring(err)))
    return
  end
  exportWin = exportWin or ns.UI:CreateTextWindow(L["EXPORT_TITLE"], 480, 300)
  exportWin.title:SetText(string.format(L["EXPORT_TITLE_FMT"], n, #str))
  exportWin:SetText(str)
  exportWin:Show()
  exportWin:SelectAll()
end

function EF:ShowImport()
  importWin = importWin or ns.UI:CreateTextWindow(L["IMPORT_TITLE"], 480, 300, true)
  importWin:SetText("")
  importWin.ok:SetScript("OnClick", function()
    local prepared, err = ns.Learn:PrepareImport(importWin.box:GetText())
    if not prepared then
      ns:Print(string.format(L["IMPORT_FAILED"], tostring(err)))
      return
    end
    importWin:Hide()
    ns.UI:Confirm(string.format(L["IMPORT_CONFIRM_FMT"], prepared.total, prepared.new), function()
      local total, new = ns.Learn:CommitImport(prepared)
      ns:Print(string.format(L["IMPORT_DONE_FMT"], total, new))
    end)
  end)
  importWin:Show()
  importWin.box:SetFocus()
end
