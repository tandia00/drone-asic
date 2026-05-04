#include "../sahel1.h"

int ndvi_run(const uint8_t *r, const uint8_t *n, int8_t *o, int npix, int8_t threshold)
{
    NDVI_RED    = (uint32_t)r;
    NDVI_NIR    = (uint32_t)n;
    NDVI_OUT    = (uint32_t)o;
    NDVI_NPIX   = (uint32_t)npix;
    NDVI_THRESH = (uint32_t)(uint8_t)threshold;
    NDVI_CTRL   = 0x1; /* start */
    while (NDVI_STAT & 0x1) ; /* busy */
    return (int)NDVI_HEALTHY;
}
