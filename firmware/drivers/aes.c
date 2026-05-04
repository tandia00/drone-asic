#include "../sahel1.h"

void aes_encrypt(const uint32_t key[4], const uint32_t in[4], uint32_t out[4])
{
    for (int i = 0; i < 4; i++) AES_KEY(i) = key[i];
    for (int i = 0; i < 4; i++) AES_DIN(i) = in[i];
    AES_CTRL = 0x1;
    while (AES_STAT & 0x1) ;
    for (int i = 0; i < 4; i++) out[i] = AES_DOUT(i);
}
