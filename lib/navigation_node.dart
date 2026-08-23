/// A nested `Navigator`: dialogs, sheets and pushed routes stay inside the
/// screen that opened them, and the system back reaches the innermost node
/// first.
library;

// Listed rather than exported whole. A name is public from the moment it
// ships, and the next helper written beside these three would join the API
// without anybody deciding that.
export 'src/navigation_node.dart'
    show NavigationNode, NodeNavigatorState, PreviousNavigatorExtension;
