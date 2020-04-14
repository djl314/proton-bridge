// Copyright (c) 2020 Proton Technologies AG
//
// This file is part of ProtonMail Bridge.
//
// ProtonMail Bridge is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// ProtonMail Bridge is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with ProtonMail Bridge.  If not, see <https://www.gnu.org/licenses/>.

package bridge

import (
	"testing"

	"github.com/ProtonMail/proton-bridge/pkg/pmapi"
	gomock "github.com/golang/mock/gomock"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testNewUser(m mocks) *User {
	m.clientManager.EXPECT().GetClient("user").Return(m.pmapiClient).MinTimes(1)

	mockConnectedUser(m)

	gomock.InOrder(
		m.pmapiClient.EXPECT().GetEvent("").Return(testPMAPIEvent, nil).MaxTimes(1),
		m.pmapiClient.EXPECT().GetEvent(testPMAPIEvent.EventID).Return(testPMAPIEvent, nil).MaxTimes(1),
		m.pmapiClient.EXPECT().ListMessages(gomock.Any()).Return([]*pmapi.Message{}, 0, nil).MaxTimes(1),
	)

	user, err := newUser(m.PanicHandler, "user", m.eventListener, m.credentialsStore, m.clientManager, m.storeCache, "/tmp")
	assert.NoError(m.t, err)

	err = user.init(nil)
	assert.NoError(m.t, err)

	return user
}

func testNewUserForLogout(m mocks) *User {
	m.clientManager.EXPECT().GetClient("user").Return(m.pmapiClient).MinTimes(1)

	mockConnectedUser(m)

	gomock.InOrder(
		m.pmapiClient.EXPECT().GetEvent("").Return(testPMAPIEvent, nil).MaxTimes(1),
		m.pmapiClient.EXPECT().GetEvent(testPMAPIEvent.EventID).Return(testPMAPIEvent, nil).MaxTimes(1),
		m.pmapiClient.EXPECT().ListMessages(gomock.Any()).Return([]*pmapi.Message{}, 0, nil).MaxTimes(1),
	)

	user, err := newUser(m.PanicHandler, "user", m.eventListener, m.credentialsStore, m.clientManager, m.storeCache, "/tmp")
	assert.NoError(m.t, err)

	err = user.init(nil)
	assert.NoError(m.t, err)

	return user
}

func cleanUpUserData(u *User) {
	_ = u.clearStore()
}

func _TestNeverLongStorePath(t *testing.T) { // nolint[unused]
	assert.Fail(t, "not implemented")
}

func TestClearStoreWithStore(t *testing.T) {
	m := initMocks(t)
	defer m.ctrl.Finish()

	user := testNewUserForLogout(m)
	defer cleanUpUserData(user)

	require.Nil(t, user.store.Close())
	user.store = nil
	assert.Nil(t, user.clearStore())
}

func TestClearStoreWithoutStore(t *testing.T) {
	m := initMocks(t)
	defer m.ctrl.Finish()

	user := testNewUserForLogout(m)
	defer cleanUpUserData(user)

	assert.NotNil(t, user.store)
	assert.Nil(t, user.clearStore())
}
