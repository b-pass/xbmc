/*
 *      Copyright (C) 2013 Team XBMC
 *      http://xbmc.org
 *
 *  This Program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2, or (at your option)
 *  any later version.
 *
 *  This Program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with XBMC; see the file COPYING.  If not, see
 *  <http://www.gnu.org/licenses/>.
 *
 */

#include "MultiProvider.h"
#include "utils/XBMCTinyXML.h"
#include "threads/SingleLock.h"

CMultiProvider::CMultiProvider(const TiXmlNode *first, int parentID)
 : IListProvider(parentID)
{
  for (const TiXmlNode *content = first; content; content = content->NextSiblingElement("content"))
  {
    IListProviderPtr sub(IListProvider::CreateSingle(content, parentID));
    if (sub)
      m_providers.push_back(sub);
  }
}

bool CMultiProvider::Update(bool forceRefresh)
{
  bool result = false;
  for (auto& provider : m_providers)
    result |= provider->Update(forceRefresh);
  return result;
}

void CMultiProvider::Fetch(std::vector<CGUIListItemPtr> &items) const
{
  CSingleLock lock(m_section);
  std::vector<CGUIListItemPtr> subItems;
  items.clear();
  m_itemMap.clear();
  for (auto const& provider : m_providers)
  {
    provider->Fetch(subItems);
    for (auto& item : subItems)
    {
      m_itemMap[item.get()] = provider;
      items.push_back(item);
    }
    subItems.clear();
  }
}

bool CMultiProvider::IsUpdating() const
{
  bool result = false;
  for (auto const& provider : m_providers)
    result |= provider->IsUpdating();
  return result;
}

void CMultiProvider::Reset(bool immediately)
{
  if (immediately)
  {
    CSingleLock lock(m_section);
    m_itemMap.clear();
  }

  for (auto const& provider : m_providers)
    provider->Reset(immediately);
}

bool CMultiProvider::OnClick(const CGUIListItemPtr &item)
{
  CSingleLock lock(m_section);
  auto it = m_itemMap.find(item.get());
  if (it != m_itemMap.end())
    return it->second->OnClick(item);
  else
    return false;
}

bool CMultiProvider::OnInfo(const CGUIListItemPtr &item)
{
  CSingleLock lock(m_section);
  auto it = m_itemMap.find(item.get());
  if (it != m_itemMap.end())
    return it->second->OnInfo(item);
  else
    return false;
}

bool CMultiProvider::OnContextMenu(const CGUIListItemPtr &item)
{
  CSingleLock lock(m_section);
  auto it = m_itemMap.find(item.get());
  if (it != m_itemMap.end())
    return it->second->OnContextMenu(item);
  else
    return false;
}
