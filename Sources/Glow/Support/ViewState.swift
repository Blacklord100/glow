import SwiftUI

// Keep using SwiftUI's stable property-wrapper State on CLT installations where
// the newer SDK declares a same-named macro but omits its SwiftUIMacros plugin.
typealias ViewState<Value> = SwiftUI.State<Value>
