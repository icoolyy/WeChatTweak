// Adapted from upstream-wechat: stable ID and verified epoch replace raw URLs.
export interface SearchResult { id: string; arg: string; title: string; subtitle: string; session: string }
export interface SearchState {
  items: SearchResult[]; recentContacts: SearchResult[]; pinnedContacts: SearchResult[];
  isLoading: boolean; searchText: string; session?: string; error?: string;
}
